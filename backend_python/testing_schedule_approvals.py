"""Offline API integration tests. Uses synthetic records in a temporary folder.

Run: .venv/Scripts/python testing_schedule_approvals.py
No production credentials, databases or mock_data files are read or modified.
"""
import copy
import os
import shutil
import unittest
from pathlib import Path
from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from unittest.mock import patch

os.environ["DB_BACKEND"] = "mock"
os.environ["USE_MOCK_DB"] = "1"

from fastapi.testclient import TestClient
import api
import workflow_auth
from mock_firestore import MockFirestoreClient

START, END = "2099-01-01", "2099-01-15"


class ApprovalFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(__file__).resolve().parent / (".approval-test-" + uuid4().hex)
        self.tmp.mkdir(mode=0o777)
        api.db = MockFirestoreClient(str(self.tmp))
        self.repo = api.repo
        self.client = TestClient(api.app)
        self.headers = {}
        for username, role in (("admin", "admin"), ("assistant", "assistantSecurity"), ("commander", "areaCommander")):
            self.repo.users.upsert(username, {"username": username, "name": username.title(), "role": role, "active": True})
            token = workflow_auth.issue_session(self.repo, username, role)
            self.headers[username] = {"Authorization": f"Bearer {token}"}
        for n in (1, 2):
            sid, eid = f"STA{n}", f"GUARD{n}"
            self.repo.stations.upsert(sid, {"id": sid, "name": f"Station {n}", "isActive": True})
            self.repo.employees.upsert(eid, {"id": eid, "name": f"Guard {n}", "type": "regular", "isActive": True, "assignedShift": "morning", "assignedStation": f"Station {n}"})
            days = [{"date": (date.fromisoformat(START) + timedelta(days=i)).isoformat(), "entries": [{
                "id": f"{eid}-{i}", "employeeId": eid, "employeeName": f"Guard {n}",
                "shift": "Morning", "post": "Roving", "timeIn": "05:00", "timeOut": "14:00",
                "isReliever": False,
            }]} for i in range(15)]
            self.repo.schedules.upsert(sid, {"id": sid, "stationId": sid, "stationName": f"Station {n}", "startDate": START, "endDate": END, "createdAt": "2098-12-20T00:00:00+00:00", "status": "unpublished", "days": days})
        token = workflow_auth.issue_session(self.repo, "GUARD1", "regular")
        self.headers["guard"] = {"Authorization": f"Bearer {token}"}
        self.repo.employees.upsert("REL1", {"id": "REL1", "name": "Cover Guard", "type": "reliever", "isActive": True, "assignedStation": "Station 1", "assignedShift": "morning"})

    def tearDown(self):
        self.client.close()
        api.db = None
        # Delete only the synthetic directory this test created in the workspace.
        assert self.tmp.parent == Path(__file__).resolve().parent
        assert self.tmp.name.startswith(".approval-test-")
        shutil.rmtree(self.tmp)

    def request(self, method, path, user="admin", **kwargs):
        return self.client.request(method, path, headers=self.headers[user], **kwargs)

    def submit(self):
        result = self.request("POST", "/schedule-approvals/submit", json={"startDate": START, "endDate": END, "preparedBy": "Scheduler"})
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()["approval"]

    def decide(self, record, user, action="approve", comment=""):
        return self.request("POST", f"/schedule-approvals/{record['id']}/decision", user=user,
                            json={"version": record["version"], "action": action, "comment": comment})

    def approve(self):
        record = self.submit()
        for user in ("assistant", "commander"):
            result = self.decide(record, user)
            self.assertEqual(result.status_code, 200, result.text)
            record = result.json()["approval"]
        return record

    def export(self):
        return self.request("POST", "/schedule-report", json={"startDate": START, "endDate": END})

    def test_sequential_approval_publishes_entire_period_and_unlocks_export(self):
        self.assertEqual(self.export().status_code, 409)
        record = self.submit()
        self.assertEqual(self.decide(record, "commander").status_code, 409)
        self.assertEqual(self.decide(record, "admin").status_code, 403)
        self.assertTrue(all(s["status"] == "unpublished" for s in self.repo.schedules.list()))
        result = self.decide(record, "assistant")
        self.assertEqual(result.status_code, 200, result.text)
        record = result.json()["approval"]
        self.assertEqual(record["status"], "pending_commander")
        self.assertEqual(self.export().status_code, 409)
        self.assertEqual(self.decide(record, "assistant").status_code, 409)
        result = self.decide(record, "commander")
        self.assertEqual(result.status_code, 200, result.text)
        self.assertTrue(all(s["status"] == "published" for s in self.repo.schedules.list()))
        response = self.export()
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(len(response.json()["schedules"]), 2)
        self.assertEqual(len(self.repo.employee_notifications.list()), 2)
        self.assertTrue(self.repo.workflow_notifications.find(username="admin"))

    def test_old_publish_endpoints_and_role_bypasses_are_blocked(self):
        self.assertEqual(self.client.get('/schedule-approvals').status_code, 401)
        self.assertEqual(self.request("POST", "/schedules/STA1/publish").status_code, 409)
        self.assertEqual(self.request("POST", "/schedules/publish-all").status_code, 409)
        self.assertEqual(self.request("GET", "/schedule-approvals", user="guard").status_code, 403)
        for user in ("assistant", "commander", "guard"):
            self.assertEqual(self.request("POST", "/schedules/generate", user=user, json={"group": 1, "startDate": START}).status_code, 403)
            self.assertEqual(self.request("GET", "/officials", user=user).status_code, 403)
        self.assertEqual(self.request("GET", "/employees/GUARD2", user="guard").status_code, 403)

    def test_complete_period_required_and_repeated_submission_refused(self):
        self.repo.stations.upsert("STA3", {"id": "STA3", "name": "Third", "isActive": True})
        result = self.request("POST", "/schedule-approvals/submit", json={"startDate": START, "endDate": END})
        self.assertEqual(result.status_code, 409)
        self.assertIn("Third", result.text)
        self.repo.stations.delete("STA3")
        self.submit()
        result = self.request("POST", "/schedule-approvals/submit", json={"startDate": START, "endDate": END})
        self.assertEqual(result.status_code, 409)

    def test_return_requires_comment_and_resubmission_restarts_at_assistant(self):
        record = self.submit()
        record = self.decide(record, "assistant").json()["approval"]
        self.assertEqual(self.decide(record, "commander", "return").status_code, 400)
        result = self.decide(record, "commander", "return", "Please correct the shift times.")
        self.assertEqual(result.status_code, 200, result.text)
        self.assertEqual(result.json()["approval"]["status"], "returned")
        response = self.request("PUT", "/schedules/STA1/posts", json={"employeeId": "GUARD1", "post": "Platform"})
        self.assertEqual(response.status_code, 200, response.text)
        second = self.submit()
        self.assertEqual(second["revision"], 2)
        self.assertEqual(second["status"], "pending_assistant")
        self.assertEqual(self.decide(record, "commander").status_code, 409)
        self.assertEqual(self.repo.schedule_approvals.get(record["id"])["schedules"][0]["days"][0]["entries"][0]["post"], "Roving")

    def test_review_locks_mutations_and_regeneration(self):
        self.submit()
        operations = [
            ("DELETE", "/schedules/STA1", None), ("DELETE", "/schedules", None),
            ("POST", "/schedules/STA1/unpublish", None),
            ("PUT", "/schedules/STA1/posts", {"employeeId": "GUARD1", "post": "Platform"}),
            ("POST", "/schedules/generate", {"group": 1, "startDate": START, "overwrite": True}),
            ("DELETE", "/stations/STA1", None),
        ]
        for method, path, body in operations:
            self.assertEqual(self.request(method, path, json=body).status_code, 409, path)

    def test_stale_or_changed_roster_cannot_be_approved_or_exported(self):
        record = self.approve()
        schedule = self.repo.schedules.get("STA1")
        schedule["days"][0]["entries"][0]["post"] = "Tampered"
        self.repo.schedules.upsert("STA1", schedule)
        self.assertEqual(self.export().status_code, 409)
        self.assertEqual(self.decide(record, "commander").status_code, 409)

    def test_revision_withdraws_all_and_preserves_approval_evidence(self):
        record = self.approve()
        response = self.request("POST", f"/schedule-approvals/{record['id']}/revise", json={"version": record["version"], "comment": "Planned shift revision"})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(all(s["status"] == "unpublished" for s in self.repo.schedules.list()))
        self.assertEqual(self.export().status_code, 409)
        old = self.repo.schedule_approvals.get(record["id"])
        self.assertEqual(len([e for e in old["events"] if e["action"] == "approve"]), 2)
        second = self.submit()
        self.assertEqual(second["revision"], 2)
        self.assertEqual(self.decide(second, "commander").status_code, 409)

    def test_emergency_replacement_is_immediate_audited_and_exportable(self):
        record = self.approve()
        original = copy.deepcopy(self.repo.schedule_approvals.get(record["id"])["schedules"])
        response = self.request("POST", "/replacements/apply", json={
            "date": START, "station": "Station 1", "shift": "Morning",
            "absentEmployeeId": "GUARD1", "absentEmployeeName": "Guard 1",
            "replacementEmployeeId": "REL1", "reason": "Guard reported sick",
        })
        self.assertEqual(response.status_code, 200, response.text)
        updated = self.repo.schedule_approvals.get(record["id"])
        self.assertEqual(updated["schedules"], original)
        self.assertEqual(updated["status"], "approved")
        self.assertEqual(len(updated["amendments"]), 1)
        self.assertEqual(updated["amendments"][0]["username"], "admin")
        self.assertEqual(updated["amendments"][0]["comment"], "Guard reported sick")
        self.assertEqual(self.repo.schedules.get("STA1")["status"], "published")
        response = self.export()
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["schedules"][0]["days"][0]["entries"][0]["employeeId"], "REL1")
        for user in ("assistant", "commander"):
            self.assertTrue(any(n["title"] == "Emergency schedule amendment" for n in self.repo.workflow_notifications.find(username=user)))

    def test_failed_final_publication_rolls_back_the_entire_period(self):
        record = self.submit()
        record = self.decide(record, "assistant").json()["approval"]
        original = api._schedule_publish_notifications
        def fail_on_second(schedule):
            if schedule["id"] == "STA2":
                raise RuntimeError("simulated publication failure")
            return original(schedule)
        with patch.object(api, "_schedule_publish_notifications", fail_on_second):
            with self.assertRaises(RuntimeError):
                self.decide(record, "commander")
        self.assertTrue(all(s["status"] == "unpublished" for s in self.repo.schedules.list()))
        self.assertEqual(self.repo.schedule_approvals.get(record["id"])["status"], "pending_commander")
        self.assertFalse(self.repo.employee_notifications.list())

    def test_concurrent_approvals_only_apply_once(self):
        record = self.submit()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.decide(record, "assistant").status_code, range(2)))
        self.assertEqual(sorted(results), [200, 409])
        self.assertEqual(len(self.repo.schedule_approvals.get(record["id"])["events"]), 2)

    def test_deactivated_accounts_cannot_use_existing_sessions(self):
        response = self.request("PUT", "/officials/assistant", json={"active": False})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.request("GET", "/schedule-approvals", user="assistant").status_code, 401)

    def test_guard_only_sees_the_roster_after_final_approval(self):
        record = self.submit()
        url = "/employees/GUARD1/schedule"
        self.assertFalse(self.request("GET", url, user="guard").json()["shifts"])
        record = self.decide(record, "assistant").json()["approval"]
        self.assertFalse(self.request("GET", url, user="guard").json()["shifts"])
        self.decide(record, "commander")
        self.assertEqual(len(self.request("GET", url, user="guard").json()["shifts"]), 15)

    def test_official_account_creation_login_password_change_and_reset(self):
        # Isolate the credential file as well as the repository.
        import mock_auth
        with patch.object(mock_auth, "_users", {}), patch.object(mock_auth, "_AUTH_FILE", str(self.tmp / "credentials.json")):
            response = self.request("POST", "/officials", json={"username": "official3", "name": "Third Official", "role": "assistantSecurity"})
            self.assertEqual(response.status_code, 200, response.text)
            password = response.json()["temporaryPassword"]
            login = self.client.post("/login", json={"username": "official3", "password": password})
            self.assertEqual(login.status_code, 200, login.text)
            self.assertEqual(login.json()["role"], "assistantSecurity")
            self.assertIsNone(self.repo.employees.get("official3"))
            old_headers = {"Authorization": f"Bearer {login.json()['token']}"}
            changed = self.client.post("/change-password", json={"username": "official3", "currentPassword": password, "newPassword": "Example-New-Password-123"})
            self.assertEqual(changed.status_code, 200, changed.text)
            self.assertEqual(self.client.get("/account", headers=old_headers).status_code, 401)
            new_headers = {"Authorization": f"Bearer {changed.json()['token']}"}
            self.assertEqual(self.client.get("/account", headers=new_headers).status_code, 200)
            reset = self.request("POST", "/officials/official3/reset-password")
            self.assertEqual(reset.status_code, 200, reset.text)
            self.assertEqual(self.client.get("/account", headers=new_headers).status_code, 401)
            login = self.client.post("/login", json={"username": "official3", "password": reset.json()["temporaryPassword"]})
            self.assertEqual(login.status_code, 200)

    def test_legacy_published_schedules_do_not_get_fabricated_approvals(self):
        for schedule in self.repo.schedules.list():
            self.repo.schedules.update(schedule["id"], {"status": "published"})
        self.assertEqual(self.export().status_code, 409)
        record = self.submit()
        self.assertEqual(record["status"], "pending_assistant")
        self.assertTrue(all(s["status"] == "unpublished" for s in self.repo.schedules.list()))

    def test_official_updates_only_own_name_and_preserves_decision_history(self):
        record = self.approve()
        original = copy.deepcopy(self.repo.schedule_approvals.get(record["id"]))
        result = self.request("PUT", "/account", user="assistant", json={"name": "  Updated Assistant  "})
        self.assertEqual(result.status_code, 200, result.text)
        self.assertEqual(result.json()["name"], "Updated Assistant")
        self.assertEqual(self.request("GET", "/account", user="assistant").json()["name"], "Updated Assistant")
        self.assertEqual(self.repo.users.get("commander")["name"], "Commander")
        self.assertEqual(self.repo.schedule_approvals.get(record["id"]), original)
        # The existing session uses the updated name on a future decision.
        revised = self.request("POST", f"/schedule-approvals/{record['id']}/revise", json={"version": record["version"], "comment": "Next revision"})
        self.assertEqual(revised.status_code, 200)
        result = self.decide(self.submit(), "assistant")
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["approval"]["events"][-1]["name"], "Updated Assistant")

    def test_profile_cannot_change_role_username_or_other_accounts(self):
        for payload in ({"name": " "}, {"name": "A" * 121},
                        {"name": "Changed", "role": "admin"},
                        {"name": "Changed", "username": "commander"},
                        {"name": "Changed", "active": False}):
            result = self.request("PUT", "/account", user="assistant", json=payload)
            self.assertIn(result.status_code, (400, 422))
        for user in ("guard", "admin"):
            self.assertEqual(self.request("PUT", "/account", user=user, json={"name": "Changed"}).status_code, 403)
        self.assertEqual(self.client.put("/account", json={"name": "Changed"}).status_code, 401)
        self.assertEqual(self.repo.users.get("assistant")["name"], "Assistant")

    def test_empty_or_undefined_rosters_cannot_be_submitted(self):
        schedule = self.repo.schedules.get("STA1")
        schedule["days"][0]["entries"][0]["post"] = "Undefined"
        self.repo.schedules.upsert("STA1", schedule)
        response = self.request("POST", "/schedule-approvals/submit", json={"startDate": START, "endDate": END})
        self.assertEqual(response.status_code, 409)

        schedule["days"][0]["entries"] = []
        self.repo.schedules.upsert("STA1", schedule)
        response = self.request("POST", "/schedule-approvals/submit", json={"startDate": START, "endDate": END})
        self.assertEqual(response.status_code, 409)

    def test_guard_preferences_and_head_guard_report_history_remain_accessible(self):
        response = self.request("PUT", "/employees/GUARD1", user="guard", json={"preferredStations": ["Station 1"]})
        self.assertEqual(response.status_code, 200, response.text)
        response = self.request("PUT", "/employees/GUARD1", user="guard", json={"type": "headGuard"})
        self.assertEqual(response.status_code, 403)
        self.repo.employees.upsert("HG1", {"id": "HG1", "name": "Head Guard", "type": "headGuard", "isActive": True})
        self.headers["head"] = {"Authorization": "Bearer " + workflow_auth.issue_session(self.repo, "HG1", "headGuard")}
        for key, who in (("report1", "HG1"), ("report2", "OTHER")):
            self.repo.attendance_reports.upsert(key, {"id": key, "headGuardId": who, "submittedAt": "2099-01-01"})
        response = self.request("GET", "/attendance-reports", user="head")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual([r["id"] for r in response.json()["reports"]], ["report1"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
