#!/usr/bin/env python3

import json
import signal
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")

from gi.repository import Gdk, GLib, Gtk


def build_provider(payload):
    providers = []

    if payload.get("html_only") is not True:
        plain_bytes = GLib.Bytes.new(payload.get("text", "").encode("utf-8"))
        providers.append(
            Gdk.ContentProvider.new_for_bytes(
                "text/plain;charset=utf-8",
                plain_bytes,
            )
        )
        providers.append(
            Gdk.ContentProvider.new_for_bytes(
                "text/plain",
                plain_bytes,
            )
        )

    providers.append(
        Gdk.ContentProvider.new_for_bytes(
            "text/html",
            GLib.Bytes.new(payload.get("html", "").encode("utf-8")),
        )
    )

    if len(providers) == 1:
        return providers[0]

    return Gdk.ContentProvider.new_union(providers)


def main():
    payload = json.load(sys.stdin)

    Gtk.init()
    display = Gdk.Display.get_default()
    if display is None:
        print("No Wayland display available", file=sys.stderr)
        return 1

    clipboard = display.get_clipboard()
    if not clipboard.set_content(build_provider(payload)):
        print("Failed to set clipboard content", file=sys.stderr)
        return 1

    loop = GLib.MainLoop()

    def quit_loop(*_args):
        loop.quit()

    def on_timeout():
        loop.quit()
        return GLib.SOURCE_REMOVE

    signal.signal(signal.SIGINT, quit_loop)
    signal.signal(signal.SIGTERM, quit_loop)
    GLib.timeout_add_seconds(max(int(payload.get("timeout_seconds", 300)), 1), on_timeout)

    print("READY")
    sys.stdout.flush()
    loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
