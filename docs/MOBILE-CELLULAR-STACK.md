# GenixBit Mobile Cellular Stack

The cellular interface on GenixBit Mobile OS is designed to leverage standard Linux cellular and network services.

> [!NOTE]
> This component is in the architectural planning stage and is not yet implemented.

## Cellular Data Layer: ModemManager & NetworkManager

The cellular stack integrates standard open-source tools:
- **ModemManager:** Manages mobile broadband devices, interfaces with hardware modems via DBus, and controls SIM card profiles.
- **NetworkManager:** Controls the data connections, automatically switching between cellular networks (e.g. LTE, 5G) and Wi-Fi networks depending on availability and signal strength.

## Key Cellular Milestones

Development of the mobile stack will be divided into the following sequential milestones:

1. **Calls & SMS:**
   - Basic voice calling interface using standard voice modems.
   - Send and receive SMS text messages over standard GSM networks.
2. **IMS & VoLTE Support:**
   - Integration with IP Multimedia Subsystem (IMS) to support Voice over LTE (VoLTE).
   - High-definition voice calls and video calls.
3. **eSIM Management:**
   - Dynamic carrier provisioning and management via eSIM interfaces.
4. **Emergency Calls:**
   - Reliable emergency calling capabilities that take priority over all other processes, regardless of cellular account state or system CPU load.
