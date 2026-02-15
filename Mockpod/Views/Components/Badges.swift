import SwiftUI

/// Badge showing HTTP method with color coding
struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch method.uppercased() {
        case "GET": return .green
        case "POST": return .blue
        case "PUT": return .orange
        case "PATCH": return .purple
        case "DELETE": return .red
        case "HEAD": return .gray
        case "OPTIONS": return .teal
        default: return .secondary
        }
    }
}

/// Badge showing HTTP status code with color coding
struct StatusBadge: View {
    let code: Int

    var body: some View {
        Text("\(code)")
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .secondary
        }
    }
}
