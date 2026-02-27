from collections.abc import Generator
from typing import Any
from urllib.parse import urlparse

import requests

from dify_plugin import Tool
from dify_plugin.entities.tool import ToolInvokeMessage


class UrlToMarkdownTool(Tool):
    API_ENDPOINT = "https://markdown.new/"
    VALID_METHODS = {"auto", "ai", "browser"}

    def _validate_url(self, url: str) -> str:
        target = (url or "").strip()
        if not target:
            raise ValueError("Parameter 'url' is required.")

        parsed = urlparse(target)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("Parameter 'url' must be a valid http/https URL.")

        return target

    def _as_bool(self, value: Any, default: bool) -> bool:
        if value is None:
            return default
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"1", "true", "yes", "y", "on"}:
                return True
            if normalized in {"0", "false", "no", "n", "off"}:
                return False
        return bool(value)

    def _as_int(self, value: Any, default: int) -> int:
        if value is None:
            return default
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    def _invoke(self, tool_parameters: dict[str, Any]) -> Generator[ToolInvokeMessage]:
        url = self._validate_url(tool_parameters.get("url", ""))
        method = str(tool_parameters.get("method", "auto")).strip().lower()
        retain_images = self._as_bool(tool_parameters.get("retain_images", False), default=False)
        timeout_seconds = self._as_int(tool_parameters.get("timeout_seconds", 60), default=60)
        include_response_meta = self._as_bool(
            tool_parameters.get("include_response_meta", True), default=True
        )

        if method not in self.VALID_METHODS:
            raise ValueError("Parameter 'method' must be one of: auto, ai, browser.")

        timeout_seconds = max(5, min(300, timeout_seconds))

        payload: dict[str, Any] = {
            "url": url,
            "method": method,
        }
        if retain_images:
            payload["retain_images"] = True

        try:
            response = requests.post(
                self.API_ENDPOINT,
                json=payload,
                timeout=timeout_seconds,
            )
            response.raise_for_status()
        except requests.exceptions.Timeout:
            raise ValueError(f"markdown.new request timed out after {timeout_seconds} seconds.")
        except requests.exceptions.HTTPError as e:
            status_code = e.response.status_code if e.response is not None else "unknown"
            response_text = ""
            if e.response is not None and e.response.text:
                response_text = e.response.text.strip()
            response_text = response_text[:500]

            rate_limit_remaining = ""
            rate_limit_reset = ""
            if e.response is not None:
                rate_limit_remaining = e.response.headers.get("x-rate-limit-remaining", "")
                rate_limit_reset = e.response.headers.get("x-rate-limit-reset", "")

            details = f"markdown.new request failed (HTTP {status_code}). payload={payload}."
            if rate_limit_remaining or rate_limit_reset:
                details += (
                    f" rate_limit_remaining={rate_limit_remaining or 'unknown'},"
                    f" rate_limit_reset={rate_limit_reset or 'unknown'}."
                )
            if response_text:
                details += f" response={response_text}"
            raise ValueError(details)
        except requests.exceptions.RequestException as e:
            raise ValueError(f"markdown.new request failed: {str(e)}")

        markdown = response.text or ""

        if include_response_meta:
            output = {
                "url": url,
                "method": method,
                "retain_images": retain_images,
                "markdown": markdown,
                "meta": {
                    "status_code": response.status_code,
                    "content_type": response.headers.get("content-type", ""),
                    "x_markdown_tokens": response.headers.get("x-markdown-tokens", ""),
                    "x_rate_limit_remaining": response.headers.get("x-rate-limit-remaining", ""),
                    "x_rate_limit_limit": response.headers.get("x-rate-limit-limit", ""),
                    "x_rate_limit_reset": response.headers.get("x-rate-limit-reset", ""),
                },
            }
            yield self.create_json_message(output)

        yield self.create_text_message(markdown)
