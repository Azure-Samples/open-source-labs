#!/usr/bin/env python3

"""Offline checks for the parts of e2e.py that must be right before a cluster exists.

This needs no cluster, no network, and no third-party package: it stubs the
`requests` module so `e2e.py` can be imported with the standard library alone.
It exists because the secret-scrubbing and endpoint-identity logic are the two
places where a mistake is invisible in a passing run — a leaked password or a
gate that silently accepts the wrong host both look like success.
"""

import io
import sys
import types
import unittest
import unittest.mock
from urllib.parse import urlsplit


def install_requests_stub() -> None:
    """Provide the minimum `requests` surface that importing e2e.py touches."""
    if "requests" in sys.modules:
        return
    requests_stub = types.ModuleType("requests")
    exceptions_stub = types.ModuleType("requests.exceptions")

    class RequestException(Exception):
        pass

    class SSLError(RequestException):
        pass

    class Response:
        def __init__(self, url: str = "", status_code: int = 200, text: str = ""):
            self.url = url
            self.status_code = status_code
            self.text = text
            self.history: list = []

    class Session:
        def __init__(self):
            self.cookies: list = []

    exceptions_stub.SSLError = SSLError
    exceptions_stub.RequestException = RequestException
    requests_stub.exceptions = exceptions_stub
    requests_stub.RequestException = RequestException
    requests_stub.Response = Response
    requests_stub.Session = Session
    requests_stub.get = lambda *args, **kwargs: Response()
    sys.modules["requests"] = requests_stub
    sys.modules["requests.exceptions"] = exceptions_stub


install_requests_stub()
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))

import e2e  # noqa: E402


class FakeResponse:
    def __init__(self, url: str):
        self.url = url


class ScrubbingTest(unittest.TestCase):
    def setUp(self):
        e2e._REDACTED_VALUES.clear()

    def test_registered_secret_is_replaced(self):
        e2e.register_secret("s3cret-password-value")
        self.assertEqual(
            e2e.scrub("login failed for s3cret-password-value"),
            "login failed for <redacted>",
        )

    def test_secret_is_scrubbed_from_stdout(self):
        e2e.register_secret("s3cret-password-value")
        buffer = io.StringIO()
        with unittest.mock.patch("sys.stdout", buffer):
            e2e.emit("password was s3cret-password-value")
        self.assertNotIn("s3cret-password-value", buffer.getvalue())

    def test_secret_is_scrubbed_from_stderr(self):
        e2e.register_secret("s3cret-password-value")
        buffer = io.StringIO()
        with unittest.mock.patch("sys.stderr", buffer):
            e2e.emit_error("password was s3cret-password-value")
        self.assertNotIn("s3cret-password-value", buffer.getvalue())

    def test_trivially_short_values_are_not_registered(self):
        # Redacting a 1-3 character value would corrupt unrelated output
        # without protecting anything worth protecting.
        e2e.register_secret("ab")
        self.assertEqual(e2e.scrub("ab cd"), "ab cd")


class EndpointTest(unittest.TestCase):
    def test_https_endpoint_is_accepted_and_normalized(self):
        self.assertEqual(
            e2e.require_https_endpoint("https://kubeflow.example.com/"),
            "https://kubeflow.example.com",
        )

    def test_http_endpoint_is_rejected(self):
        with self.assertRaises(e2e.GateError):
            e2e.require_https_endpoint("http://kubeflow.example.com")

    def test_same_host_over_https_is_accepted(self):
        response = FakeResponse("https://kubeflow.example.com/dashboard")
        self.assertTrue(
            e2e.same_endpoint_host(response, "https://kubeflow.example.com")
        )

    def test_other_host_is_rejected(self):
        response = FakeResponse("https://elsewhere.example.com/dashboard")
        self.assertFalse(
            e2e.same_endpoint_host(response, "https://kubeflow.example.com")
        )

    def test_downgrade_to_http_is_rejected(self):
        response = FakeResponse("http://kubeflow.example.com/dashboard")
        self.assertFalse(
            e2e.same_endpoint_host(response, "https://kubeflow.example.com")
        )


class MarkerTest(unittest.TestCase):
    def test_dashboard_marker_matches_case_insensitively(self):
        self.assertTrue(
            e2e.marker_in_body("<title>KUBEFLOW CENTRAL DASHBOARD</title>",
                               e2e.DASHBOARD_MARKERS)
        )

    def test_jupyterlab_marker_matches(self):
        self.assertTrue(
            e2e.marker_in_body('<script id="jupyter-config-data">',
                               e2e.JUPYTERLAB_MARKERS)
        )

    def test_unrelated_body_does_not_match(self):
        self.assertFalse(e2e.marker_in_body("<h1>404 Not Found</h1>",
                                            e2e.DASHBOARD_MARKERS))


class RoutesTest(unittest.TestCase):
    def test_routes_are_namespaced_to_the_example_user(self):
        self.assertEqual(
            e2e.NOTEBOOK_API_PATH,
            "/jupyter/api/namespaces/kubeflow-user-example-com/notebooks",
        )
        self.assertEqual(
            e2e.JUPYTERLAB_PATH,
            "/notebook/kubeflow-user-example-com/test/lab",
        )

    def test_paths_are_relative_so_they_bind_to_the_verified_endpoint(self):
        for path in (e2e.NOTEBOOK_API_PATH, e2e.JUPYTERLAB_PATH):
            self.assertEqual(urlsplit(path).netloc, "")
            self.assertTrue(path.startswith("/"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
