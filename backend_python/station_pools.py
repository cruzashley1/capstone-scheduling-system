"""
Station -> eligible-personnel index, the group-adjacency exception rule,
and the physical line order the stations sit in.

Answers one question for the scheduler and the API: "who can possibly be
deployed at this station?" — split into two tiers:

  * preferred — the guard listed the station in `preferredStations`
    (or it is their `assignedStation`). This is the normal pool.
  * adjacent — the guard did NOT pick the station, but their home group
    is next to the station's group, so the exception rule still allows
    the assignment as a fallback:

        Group 1 <-> Group 2 <-> Group 3      (never Group 1 <-> Group 3)

A guard's "home group" is the group of their assigned station, or —
for floating personnel with no assigned station — the group most of
their preferred stations fall in.

The index is cheap to build (one pass over employees), so it is computed
on demand from the already-loaded station/employee lists rather than
persisted; persisting it in Firestore would just add documents that go
stale every time an employee edits their preferences.
"""

# Mirrors station_grouping.dart: stations sorted by ID, then
# Group 1 = 1-8, Group 2 = 9-17, Group 3 = 18-25 (0-based slices).
GROUP_RANGES = {1: (0, 8), 2: (8, 17), 3: (17, 25)}

# The exception rule: personnel may also be deployed one group over,
# never two — Group 1 guards must not end up in far-away Group 3.
ADJACENT_GROUPS = {1: (2,), 2: (1, 3), 3: (2,)}

# How many stations up or down the line a guard may be pushed to top up
# their working days. The station list in ID order IS the physical order
# of the line (Fernando Poe Jr. -> ... -> Dr. Santos), so the difference
# between two stations' positions is how many stops apart they are.
#
# 4 is deliberately below the 8-station width of the narrowest group, so
# this radius can never reach two groups over: the group-adjacency
# exception rule above is satisfied automatically rather than having to
# be re-checked (Group 1 ends at index 7 and Group 3 starts at index 17,
# ten stops apart).
MAX_STATION_DISTANCE = 4


def sort_stations(stations):
    return sorted(stations, key=lambda s: s.get("id", ""))


def station_groups(stations):
    """{station name: group number} for the full sorted station list."""
    ordered = sort_stations(stations)
    group_of = {}
    for group, (lo, hi) in GROUP_RANGES.items():
        for station in ordered[lo:hi]:
            group_of[station["name"].strip()] = group
    return group_of


def line_order(stations):
    """{station name: position on the line}, 0-based.

    Stations are stored in the order they physically run, so sorting by
    ID is the line itself — the same sort `station_groups` slices the
    groups out of. Position differences are therefore stops apart, which
    is what `distance` below trades on.
    """
    return {station["name"].strip(): i
            for i, station in enumerate(sort_stations(stations))}


def distance(order, a, b):
    """How many stops apart two stations are, or None when either name
    isn't on the line (a stale station name on an employee record)."""
    first, second = order.get((a or "").strip()), order.get((b or "").strip())
    if first is None or second is None:
        return None
    return abs(first - second)


def nearby_stations(order, name, max_distance=MAX_STATION_DISTANCE):
    """Every station within `max_distance` stops of `name`, nearest
    first, the station itself included at distance 0.

    Returns [(station name, distance), ...]. Ties (the stop before and
    the stop after are both 1 away) come out in line order, so callers
    that need a preference between them apply their own tie-break."""
    origin = order.get((name or "").strip())
    if origin is None:
        return []
    return sorted(
        ((other, abs(pos - origin)) for other, pos in order.items()
         if abs(pos - origin) <= max_distance),
        key=lambda pair: (pair[1], order[pair[0]]),
    )


def deployable_groups(home_group):
    """Groups a guard from `home_group` may be deployed to."""
    if home_group not in ADJACENT_GROUPS:
        return ()
    return (home_group,) + ADJACENT_GROUPS[home_group]


def home_group(employee, group_of):
    """The guard's own group: their assigned station's group, or the
    majority group of their preferred stations for floating personnel.
    None when the record carries no recognisable station at all."""
    assigned = (employee.get("assignedStation") or "").strip()
    if assigned in group_of:
        return group_of[assigned]

    votes = {}
    for name in employee.get("preferredStations") or []:
        group = group_of.get(name.strip())
        if group:
            votes[group] = votes.get(group, 0) + 1
    if not votes:
        return None
    # Ties break toward the lower group number for determinism.
    return min(votes, key=lambda g: (-votes[g], g))


def _prefers(employee, station_name):
    if (employee.get("assignedStation") or "").strip() == station_name:
        return True
    return station_name in (p.strip()
                            for p in employee.get("preferredStations") or [])


def build_station_pools(stations, employees):
    """The Station Name -> possible-personnel index.

    Returns {station name: {"group": n, "preferred": [emp, ...],
    "adjacent": [emp, ...]}} where `preferred` guards picked the station
    themselves and `adjacent` guards are reachable only through the
    exception rule. Employee dicts are the caller's own objects, not
    copies."""
    group_of = station_groups(stations)
    home_of = {e["id"]: home_group(e, group_of) for e in employees}

    pools = {
        name: {"group": group, "preferred": [], "adjacent": []}
        for name, group in group_of.items()
    }
    for emp in employees:
        allowed = deployable_groups(home_of[emp["id"]])
        for name, pool in pools.items():
            if _prefers(emp, name):
                pool["preferred"].append(emp)
            elif pool["group"] in allowed:
                pool["adjacent"].append(emp)
    return pools


def group_pool(stations, employees, group):
    """The personnel pool for one group's generation run.

    Returns {"direct": [...], "adjacent": [...]}: `direct` guards belong
    to the group (assigned or preferred a station in it), `adjacent`
    guards are borrowable from a neighbouring group under the exception
    rule. The two lists never overlap."""
    group_of = station_groups(stations)
    direct, adjacent = [], []
    for emp in employees:
        assigned = (emp.get("assignedStation") or "").strip()
        prefers_group = group_of.get(assigned) == group or any(
            group_of.get(p.strip()) == group
            for p in emp.get("preferredStations") or []
        )
        if prefers_group:
            direct.append(emp)
        elif group in deployable_groups(home_group(emp, group_of)):
            adjacent.append(emp)
    return {"direct": direct, "adjacent": adjacent}
