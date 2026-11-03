import Foundation
import GameController

/// Watches for controllers and maps them onto the C pad structure.
///
/// The bit values come from `re4_ios.h`; when the real core is linked they go
/// straight into `port/whole/runtime/pad.cpp`.
final class ControllerManager {
    private(set) var displayName = "Nenhum (toque)"
    var onChange: ((String) -> Void)?

    init() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(refresh),
            name: .GCControllerDidConnect,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(refresh),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        GCController.stopWirelessControllerDiscovery()
    }

    @objc private func refresh() {
        if let controller = GCController.controllers().first {
            displayName = controller.vendorName ?? controller.productCategory
        } else {
            displayName = "Nenhum (toque)"
        }
        onChange?(displayName)
    }

    func padState() -> Re4PadState {
        var pad = Re4PadState()
        guard let controller = GCController.controllers().first,
              let gamepad = controller.extendedGamepad else {
            return pad
        }

        if gamepad.buttonA.isPressed { pad.buttons |= UInt16(RE4_PAD_A) }
        if gamepad.buttonB.isPressed { pad.buttons |= UInt16(RE4_PAD_B) }
        if gamepad.buttonX.isPressed { pad.buttons |= UInt16(RE4_PAD_X) }
        if gamepad.buttonY.isPressed { pad.buttons |= UInt16(RE4_PAD_Y) }
        if gamepad.leftShoulder.isPressed { pad.buttons |= UInt16(RE4_PAD_L) }
        if gamepad.rightShoulder.isPressed { pad.buttons |= UInt16(RE4_PAD_R) }
        if gamepad.buttonMenu.isPressed { pad.buttons |= UInt16(RE4_PAD_START) }

        if gamepad.dpad.up.isPressed { pad.buttons |= UInt16(RE4_PAD_UP) }
        if gamepad.dpad.down.isPressed { pad.buttons |= UInt16(RE4_PAD_DOWN) }
        if gamepad.dpad.left.isPressed { pad.buttons |= UInt16(RE4_PAD_LEFT) }
        if gamepad.dpad.right.isPressed { pad.buttons |= UInt16(RE4_PAD_RIGHT) }

        pad.stickX = axis(gamepad.leftThumbstick.xAxis.value)
        pad.stickY = axis(gamepad.leftThumbstick.yAxis.value)
        pad.cStickX = axis(gamepad.rightThumbstick.xAxis.value)
        pad.cStickY = axis(gamepad.rightThumbstick.yAxis.value)
        pad.triggerL = trigger(gamepad.leftTrigger.value)
        pad.triggerR = trigger(gamepad.rightTrigger.value)

        // Z has no direct iOS equivalent on a generic pad: the right trigger is
        // the closest match, mirroring the Android port's default layout.
        if gamepad.rightTrigger.value > 0.5 { pad.buttons |= UInt16(RE4_PAD_Z) }

        return pad
    }

    private func axis(_ value: Float) -> Int8 {
        Int8(max(-127, min(127, Int((value * 127).rounded()))))
    }

    private func trigger(_ value: Float) -> Int8 {
        Int8(max(0, min(127, Int((value * 127).rounded()))))
    }
}
