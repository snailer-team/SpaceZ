import Foundation

/// Best-effort LAN IPv4 address, used only to print a copy-pasteable
/// inspector URL. `en0` is Wi-Fi on iPhone; the simulator shares the Mac's
/// interfaces, where `localhost` also works.
public enum NetworkInterfaces {
    public static func primaryIPv4Address() -> String? {
        var addresses: [(name: String, address: String)] = []
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else { return nil }
        defer { freeifaddrs(interfaceList) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = pointer {
            defer { pointer = interface.pointee.ifa_next }
            guard let socketAddress = interface.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            let address = String(cString: host)
            guard !address.hasPrefix("127."), !address.hasPrefix("169.254.") else { continue }
            addresses.append((name, address))
        }

        return addresses.first { $0.name == "en0" }?.address ?? addresses.first?.address
    }
}
