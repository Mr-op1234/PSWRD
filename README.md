# PSWRD Ultimate

A secure password generation app built with Flutter that uses a custom encryption algorithm to create strong, random passwords.

## Features

- **Custom Encryption Algorithm**: Uses a proprietary algorithm that generates complex passwords from input parameters
- **Configurable Password Length**: Generate passwords of any length
- **Custom Key Support**: Use your own key or let the app generate a random one
- **Clipboard Integration**: Automatically copies generated passwords to the clipboard
- **Light and Dark Theme**: Toggle between themes for better visibility
- **Offline Operation**: All processing happens locally on your device
- **Secure Storage**: Configuration files are stored securely on your device

## How It Works

PSWRD Ultimate uses a multi-step encryption process:

1. The app creates two mapping files on first launch:
   - `AsciiMap.csv`: Contains randomly shuffled ASCII numbers and their respective characters
   - `ValueMap.csv`: Contains randomly shuffled index numbers from 0 to 35
   
2. When generating a password:
   - The user ID is converted to binary, then to a decimal less than 1
   - The key is processed into a numeric form
   - A loop is run for the specified password length
   - Each iteration uses complex mathematical operations to select characters from the value map
   - Non-linear transformations are applied to prevent predictability

## Privacy

- PSWRD Ultimate requires storage permissions solely for creating and managing the necessary configuration files
- All processing is done locally on your device
- No data is transmitted to external servers
- The developer is not responsible for password management or any potential data leakage after passwords are generated

## Installation

Download and install the APK file from the releases section.

## Requirements

- Android 5.0 (Lollipop) or higher
- Storage permission must be granted for the app to function properly

## License

See the EULA in the app for complete licensing information.

## Development

This app was developed using Flutter.
