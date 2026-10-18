#!/bin/sh
# Builds and runs Tests/AutomationTests.swift: the instance watch and the Shortcut automation logic, compiled on their
# own against CoolifyAPI, with a mock Coolify. It needs no instance, token, or network.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/hotify_automation_tests.XXXXXX")
trap 'rm -rf "$work"' EXIT

# find hands swiftc each source as one argument, so a checkout path with a space in it stays whole.
find "$repo/CoolifyAPI/Sources/CoolifyAPI" -name '*.swift' -exec \
    swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency -parse-as-library -emit-library -emit-module -module-name CoolifyAPI \
    -emit-module-path "$work/CoolifyAPI.swiftmodule" -o "$work/libCoolifyAPI.dylib" \
    -Xlinker -install_name -Xlinker @rpath/libCoolifyAPI.dylib \
    {} +

swiftc -parse-as-library -enable-bare-slash-regex -default-isolation MainActor -enable-upcoming-feature ApproachableConcurrency -I "$work" -L "$work" -lCoolifyAPI \
    -Xlinker -rpath -Xlinker "$work" -o "$work/automation-tests" \
    "$repo/Tests/AutomationTests.swift" \
    "$repo"/Hotify/Automations/AutomationTrigger.swift \
    "$repo"/Hotify/Automations/ShortcutAutomation.swift \
    "$repo"/Hotify/Automations/ShortcutPayload.swift \
    "$repo"/Hotify/Automations/ShortcutLink.swift \
    "$repo"/Hotify/Automations/AutomationDispatcher.swift \
    "$repo"/Hotify/Automations/AutomationStore.swift \
    "$repo"/Hotify/Notifications/Notice.swift \
    "$repo"/Hotify/Notifications/NotificationEvent.swift \
    "$repo"/Hotify/Notifications/InstanceWatch.swift \
    "$repo"/Hotify/Notifications/LocalActions.swift \
    "$repo"/Hotify/Instances/InstanceLink.swift \
    "$repo"/Shared/Resource/*.swift \
    "$repo"/Shared/Widgets/ResourceLink.swift \
    "$repo"/Shared/Design/Heat.swift \
    "$repo"/Shared/Backups/*.swift

"$work/automation-tests"
