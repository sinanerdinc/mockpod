<div align="center">
  <img src="Mockpod/Assets.xcassets/AppIcon.appiconset/256-mac.png" alt="Mockpod" width="128" height="128">
</div>

# Mockpod

**A powerful network interception and mocking tool for macOS users.**

Mockpod is a local proxy server that lets you inspect, modify, and mock HTTP/HTTPS traffic in real-time. It's ideal for testing edge cases, simulating backend failures, and developing frontend applications without a fully functional backend API.

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/Mockpod.git
cd Mockpod

# 2. Generate the Xcode project
brew install xcodegen  # If not already installed
xcodegen

# 3. Open in Xcode and run
open Mockpod.xcodeproj
```

---

## Features

| Feature | Description |
|---------|-------------|
| **Traffic Interception** | Capture and inspect HTTP/HTTPS requests and responses |
| **Rule-Based Mocking** | Mock API responses based on URL patterns, headers, or body content |
| **Local Proxy Server** | Lightweight, high-performance proxy server built with SwiftNIO |
| **macOS Native** | Built with SwiftUI and optimized for macOS performance and aesthetics |

---

## Requirements

- **macOS** 14.0 (Sonoma) or later
- **Xcode** 16.0 or later
- **Swift** 5.10 or later

---

## Installation

This project uses `xcodegen` to generate the Xcode project file. This keeps the project file clean and avoids merge conflicts.

### Prerequisites

**Homebrew** (if not installed):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Install XcodeGen**:

```bash
brew install xcodegen
```

### Building the Project

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/Mockpod.git
   cd Mockpod
   ```

2. **Generate the Xcode project**
   ```bash
   xcodegen
   ```

3. **Open in Xcode**
   ```bash
   open Mockpod.xcodeproj
   ```

4. Build and run the **Mockpod** target.

---

## Usage

1. **Launch Mockpod** – Open the application
2. **Configure proxy settings** – Point your system or browser proxy to the local server (default port is usually 8080)
3. **Create a Rule Set** – Define how specific requests should be mocked
4. **Start the proxy** – Begin intercepting traffic

---

## Contributing

We welcome contributions! Here's how:

1. **Fork** the repository
2. Create a new **branch**: `git checkout -b feature/my-feature`
3. **Commit** your changes: `git commit -m 'Add some feature'`
4. **Push** to the branch: `git push origin feature/my-feature`
5. Open a **Pull Request**

Please run `xcodegen` and verify the project builds successfully before submitting a pull request.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
