import AppKit
import SwiftUI

struct InspectorPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 3) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init(_ title: String, value: String) where Content == Text {
        self.title = title
        self.content = Text(value)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

struct InspectorMetricLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            content
        }
        .font(.callout)
    }
}

struct InspectorMetric: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }
}

struct InspectorTextLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct InspectorEmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

struct CopyableValue: View {
    let value: String
    let copyValue: String
    let monospaced: Bool
    let lineLimit: Int

    init(
        _ value: String,
        copyValue: String? = nil,
        monospaced: Bool = false,
        lineLimit: Int = 1
    ) {
        self.value = value
        self.copyValue = copyValue ?? value
        self.monospaced = monospaced
        self.lineLimit = lineLimit
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyValue, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy")
        }
    }
}
