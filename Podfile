# Uncomment the next line to define a global platform for your project
platform :osx, '10.14'

target 'ControllerKeyMapper' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for ControllerKeyMapper
  pod 'JoyConSwift', '0.2.1'

end

# JoyConSwift 0.2.1 reads multi-byte values from HID byte streams via
# `UnsafePointer.withMemoryRebound`. Under Swift 6 the stdlib traps with
# "self must be a properly aligned pointer for types Pointee and T" when
# the source offset is not aligned to the target type. Patch Utils.swift
# to use byte-wise little-endian reads (alignment-free, identical
# semantics on ARM64/x86_64). Idempotent: only patches if the upstream
# `withMemoryRebound` form is still present.
post_install do |installer|
  utils_path = File.join(__dir__, 'Pods/JoyConSwift/Source/Utils.swift')
  if File.exist?(utils_path) && File.read(utils_path).include?('withMemoryRebound')
    File.write(utils_path, <<~SWIFT)
      //
      //  Utils.swift
      //  JoyConSwift
      //
      //  Created by magicien on 2019/06/16.
      //  Copyright © 2019 DarkHorse. All rights reserved.
      //
      //  Patched by ControllerKeyMapper Podfile post_install for Swift 6
      //  alignment safety when reading HID byte streams at unaligned offsets.
      //

      import Foundation

      func ReadUInt16(from ptr: UnsafePointer<UInt8>) -> UInt16 {
          return UInt16(ptr[0]) | (UInt16(ptr[1]) << 8)
      }

      func ReadInt16(from ptr: UnsafePointer<UInt8>) -> Int16 {
          return Int16(bitPattern: ReadUInt16(from: ptr))
      }

      func ReadUInt32(from ptr: UnsafePointer<UInt8>) -> UInt32 {
          return UInt32(ptr[0])
               | (UInt32(ptr[1]) << 8)
               | (UInt32(ptr[2]) << 16)
               | (UInt32(ptr[3]) << 24)
      }

      func ReadInt32(from ptr: UnsafePointer<UInt8>) -> Int32 {
          return Int32(bitPattern: ReadUInt32(from: ptr))
      }
    SWIFT
    Pod::UI.puts "[JoyConSwift] Patched Source/Utils.swift for Swift 6 alignment safety".green
  end

  # JoyConSwift 0.2.1 opens its IOHIDManager with kIOHIDOptionsTypeSeizeDevice
  # globally, which makes any connected Joy-Con / Pro Controller invisible to
  # Steam and games. To support "controller passthrough" in ControllerKeyMapper,
  # inject a public `setSeized(_:)` method on JoyConManager that toggles the
  # manager between seize and shared mode. Idempotent: skipped when the
  # `setSeized` symbol is already present (i.e. patch already applied or
  # upstream provides it).
  mgr_path = File.join(__dir__, 'Pods/JoyConSwift/Source/JoyConManager.swift')
  if File.exist?(mgr_path)
    src = File.read(mgr_path)
    unless src.include?('func setSeized(')
      # 1) Open up two private fields so the appended extension can read/write
      #    them within the same source file (module-internal access).
      src = src.sub(/private let manager:/, 'internal let manager:')
      src = src.sub(/private var runLoop: RunLoop\? = nil/, 'internal var runLoop: RunLoop? = nil')

      # 2) Append the seize-toggle API at end of file.
      src += <<~SWIFT

        // MARK: - Passthrough (injected by ControllerKeyMapper post_install)

        extension JoyConManager {
            private static var seizedFlagKey: UInt8 = 0
            /// True while the underlying IOHIDManager is opened with seize option.
            public var isSeized: Bool {
                // Default true: 0.2.1 always opens with seize on first run().
                let n = objc_getAssociatedObject(self, &JoyConManager.seizedFlagKey) as? NSNumber
                return n?.boolValue ?? true
            }
            private func setSeizedFlag(_ value: Bool) {
                objc_setAssociatedObject(self, &JoyConManager.seizedFlagKey,
                                         NSNumber(value: value),
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }

            /// Toggle the manager's HID seize state. When `seized == false`,
            /// the manager is reopened in shared mode so that other processes
            /// (Steam, games) can see the controllers. When `seized == true`,
            /// the manager re-takes exclusive ownership.
            ///
            /// - Returns: kIOReturnSuccess on success, an IOReturn error otherwise.
            @discardableResult
            public func setSeized(_ seized: Bool) -> IOReturn {
                guard seized != self.isSeized else { return kIOReturnSuccess }
                guard let cfLoop = self.runLoop?.getCFRunLoop() else { return kIOReturnNotReady }

                let option = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)

                // Close the manager under the same option flag the previous open used.
                let prevOption: IOOptionBits = self.isSeized ? option : IOOptionBits(kIOHIDOptionsTypeNone)
                _ = IOHIDManagerClose(self.manager, prevOption)

                let openOption: IOOptionBits = seized ? option : IOOptionBits(kIOHIDOptionsTypeNone)
                IOHIDManagerScheduleWithRunLoop(self.manager, cfLoop, CFRunLoopMode.defaultMode.rawValue)
                let ret = IOHIDManagerOpen(self.manager, openOption)
                guard ret == kIOReturnSuccess else {
                    print("JoyConManager.setSeized failed: \\(ret)")
                    return ret
                }
                self.setSeizedFlag(seized)
                return kIOReturnSuccess
            }
        }
      SWIFT
      File.write(mgr_path, src)
      Pod::UI.puts "[JoyConSwift] Patched Source/JoyConManager.swift to expose setSeized(_:)".green
    end
  end
end
