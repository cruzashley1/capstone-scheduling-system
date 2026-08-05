"""
Workaround for antivirus HTTPS scanning (AVG/Avast Web Shield).

Those products intercept HTTPS by re-signing every connection with their
own root certificate. Google's libraries then fail with
CERTIFICATE_VERIFY_FAILED because:
  * requests/google-auth verify against certifi's bundle (no AV root),
  * grpc (Firestore) verifies against its own baked-in roots (no AV root).

configure() fixes both:
  * truststore makes plain-Python TLS use the Windows certificate store,
    which trusts the AV root (and tolerates its non-strict cert fields
    that Python 3.13+ would otherwise reject),
  * for grpc it writes .ca_bundle.pem (certifi roots + every cert in the
    Windows store) and points GRPC_DEFAULT_SSL_ROOTS_FILE_PATH at it.

Call configure() BEFORE importing firebase_admin / grpc.
"""

import os
import ssl
import sys


def configure():
    if sys.platform != "win32":
        return

    try:
        import truststore
        truststore.inject_into_ssl()
    except ImportError:
        print("note: 'pip install truststore' recommended on Windows with AV")

    try:
        import certifi
        with open(certifi.where(), encoding="utf-8") as f:
            pem_parts = [f.read()]
        for store in ("ROOT", "CA"):
            for der, encoding, _ in ssl.enum_certificates(store):
                if encoding == "x509_asn":
                    pem_parts.append(ssl.DER_cert_to_PEM_cert(der))
        bundle_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), ".ca_bundle.pem"
        )
        with open(bundle_path, "w", encoding="utf-8") as f:
            f.write("\n".join(pem_parts))
        os.environ.setdefault("GRPC_DEFAULT_SSL_ROOTS_FILE_PATH", bundle_path)
    except Exception as e:
        print(f"note: could not build grpc CA bundle ({e}); continuing anyway")
