from typing import Any

from dify_plugin import ToolProvider


class MarkdownNewProvider(ToolProvider):
    def _validate_credentials(self, credentials: dict[str, Any]) -> None:
        # This provider does not require any credentials.
        pass
