import IOBluetooth
import ArgumentParser

func utilityName() -> String {
  return URL(fileURLWithPath: CommandLine.arguments.first ?? "¯\\_(ツ)_/¯").lastPathComponent
}

func getDeviceListHelpString() -> String {
    var helpString = "\nMAC Address missing. Get the MAC address from the list below (if your device is missing, pair it with your computer first):\n"
    IOBluetoothDevice.pairedDevices()?.forEach({ device in
        guard let device = device as? IOBluetoothDevice,
        let addressString = device.addressString,
        let deviceName = device.name
        else { return }
        helpString += "\n\(addressString) - \(deviceName)"
    })
    helpString += "\n"
    return helpString
}

func printDeviceList() {
    IOBluetoothDevice.pairedDevices()?.forEach({ device in
        guard let device = device as? IOBluetoothDevice,
        let addressString = device.addressString,
        let deviceName = device.name
        else { return }
        print("\(addressString) - \(deviceName)")
    })
}

func printAndNotify(_ content: String, notify: Bool) {
    if notify {
        Process.launchedProcess(launchPath: "/usr/bin/osascript", arguments: ["-e", "display notification \"\(content)\" with title \"BluetoothConnector\""])
    }

    print(content)
}

func turnOnBluetoothIfNeeded(notify: Bool) {
    guard let bluetoothHost = IOBluetoothHostController.default(),
    bluetoothHost.powerState != kBluetoothHCIPowerStateON else { return }

    // Definitely not App Store safe
    if let iobluetoothClass = NSClassFromString("IOBluetoothPreferences") as? NSObject.Type {
        let obj = iobluetoothClass.init()
        let selector = NSSelectorFromString("setPoweredOn:")
        if (obj.responds(to: selector)) {
            obj.perform(selector, with: 1)
        }
    }

    var timeWaited : UInt32 = 0
    let interval : UInt32 = 200000 // in microseconds
    while bluetoothHost.powerState != kBluetoothHCIPowerStateON {
        usleep(interval)
        timeWaited += interval
        if (timeWaited > 5000000) {
            printAndNotify("Failed to turn on Bluetooth", notify: notify)
            exit(-2)
        }
    }
}

enum ActionType {
    case Connection
    case Disconnect
}

func execute(device: String?, connectOnly: Bool, disconnectOnly: Bool, notify: Bool, statusOnly: Bool, listOnly: Bool) {
    if listOnly {
        printDeviceList()
        exit(0)
    }
    
    guard let device = device else {
        printAndNotify("Device Name or MAC Address missing", notify: notify)
        exit(-2)
    }
    
    var chosenDevice: IOBluetoothDevice? = IOBluetoothDevice(addressString: device)
    if chosenDevice == nil {
        if let deviceByName = IOBluetoothDevice.pairedDevices()?.first(where: { (current) -> Bool in
            guard let current = current as? IOBluetoothDevice else { return false }
            return current.name == device
        }) {
            chosenDevice = deviceByName as? IOBluetoothDevice
        }
    }
    
    guard let bluetoothDevice = chosenDevice else {
        printAndNotify("Device name not found", notify: notify)
        exit(-2)
    }
    
    if !bluetoothDevice.isPaired() {
        printAndNotify("Not paired to device", notify: notify)
        exit(-4)
    }

    let alreadyConnected = bluetoothDevice.isConnected()
    let shouldConnect = (connectOnly
                        || (!connectOnly && !disconnectOnly && !alreadyConnected))

    if statusOnly {
        if alreadyConnected {
            print("Connected")
        }
        else {
            print("Disconnected")
        }
        exit(0)
    }

    var error: IOReturn = -1
    var action: ActionType
    if shouldConnect {
        action = .Connection
        turnOnBluetoothIfNeeded(notify: notify)
        error = bluetoothDevice.openConnection()
    }
    else {
        action = .Disconnect
        error = bluetoothDevice.closeConnection()
    }

    if error > 0 {
        printAndNotify("Error: \(action) failed", notify: notify)
        exit(-1)
    } else if notify {
        if action == .Connection && alreadyConnected {
            printAndNotify("Already connected", notify: notify)
        }
        else if action == .Disconnect && !alreadyConnected {
            printAndNotify("Already disconnected", notify: notify)
        }
        else {
            switch action {
                case .Connection:
                    printAndNotify("Successfully connected", notify: notify)
                
                case .Disconnect:
                    printAndNotify("Successfully disconnected", notify: notify)
            }
        }
    }
}

struct BluetoothConnector: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Connect a device")
    var connect: Bool

    @Flag(name: .shortAndLong, help: "Disconnect a device")
    var disconnect: Bool

    @Flag(name: .shortAndLong, help: "Get the status of a device")
    var status: Bool
    
    @Flag(name: .shortAndLong, help: "List all paired devices.")
    var list: Bool

    @Flag(name: .shortAndLong, help: "Post a Notification Center notification")
    var notify: Bool

    @Argument(help: ArgumentHelp(
        "The MAC address of the device or device name. MAC Address Format: 00-00-00-00-00-00 or 000000000000",
        valueName: "Device Name or MAC address"))
    var device: String?

    static var configuration = CommandConfiguration(
        commandName: utilityName(),
        abstract: "Connect/disconnects Bluetooth devices.",
        discussion: "Default behavior is to toggle between connecting and disconnecting.")

    func validate() throws {
        guard connect != true || disconnect != true else {
            throw ValidationError("Can't connect and disconnect at once.")
        }

        if status {
            guard connect == false else {
                throw ValidationError("Can't connect with status flag enabled.")
            }

            guard disconnect == false else {
                throw ValidationError("Can't disconnect with status flag enabled.")
            }
        }
        
        if list {
            guard connect == false else {
                throw ValidationError("Can't connect with status flag enabled.")
            }

            guard disconnect == false else {
                throw ValidationError("Can't disconnect with status flag enabled.")
            }
        } else if device == nil {
            throw ValidationError(getDeviceListHelpString())
        }
    }

    func run() throws {
        execute(device: device, connectOnly: connect, disconnectOnly: disconnect, notify: notify, statusOnly: status, listOnly: list)
    }
}

BluetoothConnector.main()
