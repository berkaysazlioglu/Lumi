import Darwin
import Foundation

/// P1 harness'ı için bellek ölçümü (phys_footprint — Activity Monitor'la uyumlu).
enum MemoryFootprint {
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                // mach_task_self_ global'i Swift 6'da concurrency-unsafe; trap eşdeğeri kullanılır
                task_info(task_self_trap(), task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    static func footprintMB() -> Double {
        Double(footprintBytes()) / (1024 * 1024)
    }
}
