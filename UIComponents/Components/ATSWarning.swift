import SwiftUI

// MARK: - ATS Warning Sheet
struct ATSWarningSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.15)).frame(width: 48, height: 48)
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 20)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Insecure connection").font(SwingType.titleMedium)
                    Text("HTTP").font(SwingType.labelSmall).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ATSWarningRow(icon: "eye.fill", color: .orange,
                    text: "Your data travels without TLS. Anyone on the same network can intercept them.")
                ATSWarningRow(icon: "music.note.list", color: .orange,
                    text: "Your music library and listening history are visible to network observers.")
                ATSWarningRow(icon: "wifi", color: .red,
                    text: "Never use HTTP on public Wi-Fi or any network you do not fully control.")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended setup").font(SwingType.labelMedium).foregroundStyle(.secondary)
                Text("Use Cloudflare Tunnel, nginx, Caddy, or any reverse proxy with a valid TLS certificate to enable HTTPS. Cloudflare Tunnel is free and requires no port forwarding.")
                    .font(SwingType.bodySmall).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Label("Keep HTTPS", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.swingPrimary)

                Button(role: .destructive, action: onConfirm) {
                    Text("Enable anyway").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text("This can be changed in Settings › Advanced.")
                .font(SwingType.labelSmall).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}

private struct ATSWarningRow: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(color).frame(width: 20).padding(.top, 1)
            Text(text).font(SwingType.bodySmall).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Persistent insecure banner
struct InsecureBanner: View {
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill").font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Insecure connection active").font(SwingType.labelMedium)
                    Text("Your data is not encrypted. Tap to learn more.")
                        .font(SwingType.labelSmall)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).opacity(0.5)
            }
            .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small HTTP badge shown next to URL field
struct InsecureBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.open").font(.system(size: 9))
            Text("HTTP").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
    }
}
