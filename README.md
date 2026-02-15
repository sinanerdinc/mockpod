# Mockpod

Mockpod is a powerful network interception and mocking tool designed for macOS developers. It acts as a local proxy server, allowing you to inspect, modify, and mock HTTP/HTTPS traffic in real-time. This is essential for testing edge cases, simulating backend failures, and developing frontend applications without a fully functional backend API.

## Features

- **Traffic Interception**: Capture and inspect HTTP/HTTPS requests and responses.
- **Rule-Based Mocking**: Define custom rules to mock API responses based on URL patterns, headers, or body content.
- **Local Proxy Server**: Runs a lightweight, high-performance proxy server using SwiftNIO.
- **macOS Native**: Built with SwiftUI and optimized for macOS performance and aesthetics.

## Requirements

- **macOS**: 14.0 (Sonoma) or later
- **Xcode**: 16.0 or later
- **Swift**: 5.10 or later

## Installation & Setup

This project uses `xcodegen` to generate the Xcode project file. This ensures that the project file is always clean and devoid of merge conflicts.

### Prerequisites

1.  **Install Homebrew** (if not installed):
    ```bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ```

2.  **Install XcodeGen**:
    ```bash
    brew install xcodegen
    ```

### Building the Project

1.  Clone the repository:
    ```bash
    git clone https://github.com/yourusername/Mockpod.git
    cd Mockpod
    ```

2.  Generate the Xcode project:
    ```bash
    xcodegen
    ```

3.  Open the project in Xcode:
    ```bash
    open Mockpod.xcodeproj
    ```

4.  Build and run the `Mockpod` target.

## Usage

1.  Launch Mockpod.
2.  Configure your system or browser proxy settings to point to the local server (default port is usually 8080 or configurable).
3.  Create a "Rule Set" to define how specific requests should be mocked.
4.  Start the proxy to begin intercepting traffic.

## Contributing

We welcome contributions! Please follow these steps:

1.  Fork the repository.
2.  Create a new branch: `git checkout -b feature/my-feature`.
3.  Make your changes and commit them: `git commit -m 'Add some feature'`.
4.  Push to the branch: `git push origin feature/my-feature`.
5.  Submit a pull request.

Please make sure to run `xcodegen` and verify that the project builds successfully before submitting.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
