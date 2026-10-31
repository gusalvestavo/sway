import CoreAudio
import CoreMediaIO
import Foundation
import IOKit.pwr_mgt

/// Things you do at the Mac without touching it, which keep the countdown running while away
/// detection would otherwise stop it. None of the checks needs a permission.
enum Activity: String, CaseIterable {
    case calls, videos, audio

    /// Off by default for audio: people often walk away with music playing.
    var enabledByDefault: Bool { self != .audio }

    var title: String {
        switch self {
        case .calls: L("Calls and meetings")
        case .videos: L("Videos and presentations")
        case .audio: L("Music and other audio")
        }
    }

    /// Whether this is going on right now.
    var isHappening: Bool {
        switch self {
        case .calls: Self.microphoneInUse() || Self.cameraInUse()
        case .videos: Self.displayKeptAwake()
        case .audio: Self.audioDevices(scope: kAudioObjectPropertyScopeOutput).contains(where: Self.isRunning)
        }
    }

    // MARK: Microphone and speakers (Core Audio)

    private static func microphoneInUse() -> Bool {
        // Every input device, not just the default one: calls often use a headset.
        audioDevices(scope: kAudioObjectPropertyScopeInput).contains(where: isRunning)
    }

    /// The audio devices with at least one stream in `scope`.
    private static func audioDevices(scope: AudioObjectPropertyScope) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamsSize) == noErr && streamsSize > 0
        }
    }

    /// Some app is recording from or playing to this device.
    private static func isRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    // MARK: Camera (Core Media I/O)

    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var valueSize: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                             &valueSize, &value) == noErr && value != 0
        }
    }

    // MARK: Display kept awake (power assertions)

    /// Video players, browsers playing video and slideshows keep the display from sleeping.
    private static func displayKeptAwake() -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        return all.contains { pid, assertions in
            pid.int32Value != ownPID && assertions.contains { assertion in
                (assertion[kIOPMAssertionTypeKey] as? String).map(displayTypes.contains) ?? false
            }
        }
    }
}
