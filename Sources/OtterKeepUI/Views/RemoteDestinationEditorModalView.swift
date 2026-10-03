import SwiftUI
import AppKit
import Network
import OtterKeepCore
import OtterKeepStorage

/// Modal sheet for adding and editing remote 3-2-1 backup targets (S3 Cloud / SMB NAS).
public struct RemoteDestinationEditorModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var sftpAuthModeBinding: Binding<Int> {
        Binding(get: { appState.destinationEditorSFTPAuthModeIndex }, set: { appState.destinationEditorSFTPAuthModeIndex = $0 })
    }

    private var nameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorName }, set: { appState.destinationEditorName = $0 })
    }

    private var typeIndexBinding: Binding<Int> {
        Binding(get: { appState.destinationEditorTypeIndex }, set: { appState.destinationEditorTypeIndex = $0 })
    }

    private var s3EndpointBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3Endpoint }, set: { appState.destinationEditorS3Endpoint = $0 })
    }

    private var s3BucketBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3Bucket }, set: { appState.destinationEditorS3Bucket = $0 })
    }

    private var s3RegionBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3Region }, set: { appState.destinationEditorS3Region = $0 })
    }

    private var s3AccessKeyBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3AccessKeyId }, set: { appState.destinationEditorS3AccessKeyId = $0 })
    }

    private var s3SecretAccessKeyBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3SecretAccessKey }, set: { appState.destinationEditorS3SecretAccessKey = $0 })
    }

    private var s3PrefixBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3PathPrefix }, set: { appState.destinationEditorS3PathPrefix = $0 })
    }

    private var s3ForcePathStyleBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorS3ForcePathStyle }, set: { appState.destinationEditorS3ForcePathStyle = $0 })
    }

    private var smbShareURLBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbShareURL }, set: { appState.destinationEditorSmbShareURL = $0 })
    }

    private var smbMountPathBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbMountPath }, set: { appState.destinationEditorSmbMountPath = $0 })
    }

    private var smbUsernameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbUsername }, set: { appState.destinationEditorSmbUsername = $0 })
    }

    private var smbPasswordBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbPassword }, set: { appState.destinationEditorSmbPassword = $0 })
    }

    private var webdavURLBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVURL }, set: { appState.destinationEditorWebDAVURL = $0 })
    }

    private var webdavPathBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVPath }, set: { appState.destinationEditorWebDAVPath = $0 })
    }

    private var webdavUsernameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVUsername }, set: { appState.destinationEditorWebDAVUsername = $0 })
    }

    private var webdavPasswordBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVPassword }, set: { appState.destinationEditorWebDAVPassword = $0 })
    }

    private var sftpHostBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPHost }, set: { appState.destinationEditorSFTPHost = $0 })
    }

    private var sftpPortBinding: Binding<Int> {
        Binding(get: { appState.destinationEditorSFTPPort }, set: { appState.destinationEditorSFTPPort = $0 })
    }

    private var sftpUsernameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPUsername }, set: { appState.destinationEditorSFTPUsername = $0 })
    }

    private var sftpPasswordOrKeyBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPPasswordOrKey }, set: { appState.destinationEditorSFTPPasswordOrKey = $0 })
    }

    private var sftpPathBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPPath }, set: { appState.destinationEditorSFTPPath = $0 })
    }

    private var archivePackagingBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorArchivePackagingEnabled }, set: { appState.destinationEditorArchivePackagingEnabled = $0 })
    }

    private var isClientEncryptionBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorIsClientEncryptionEnabled }, set: { appState.destinationEditorIsClientEncryptionEnabled = $0 })
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorIsEnabled }, set: { appState.destinationEditorIsEnabled = $0 })
    }

    private var isS3: Bool {
        appState.destinationEditorTypeIndex == 0
    }

    private var headerIcon: String {
        switch appState.destinationEditorTypeIndex {
        case 0: return "icloud.and.arrow.up.fill"
        case 1: return "server.rack"
        case 2: return "network"
        default: return "terminal.fill"
        }
    }

    private var headerColor: Color {
        switch appState.destinationEditorTypeIndex {
        case 0: return OtterTheme.oceanicTeal
        case 1: return OtterTheme.otterAmber
        case 2: return OtterTheme.oceanicTeal
        default: return OtterTheme.accentPurple
        }
    }

    private var canSave: Bool {
        let trimmedName = appState.destinationEditorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }

        switch appState.destinationEditorTypeIndex {
        case 0:
            return !appState.destinationEditorS3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !appState.destinationEditorS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return !appState.destinationEditorSmbShareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2:
            return !appState.destinationEditorWebDAVURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 3:
            return !appState.destinationEditorSFTPHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !appState.destinationEditorSFTPUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Divider()

            // MARK: - Form Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Destination Overview (Name & Type Selection)
                    destinationOverviewSection

                    // 2. Storage Backend Specific Form
                    switch appState.destinationEditorTypeIndex {
                    case 0:
                        s3ConfigurationCard
                    case 1:
                        smbConfigurationCard
                    case 2:
                        webdavConfigurationCard
                    default:
                        sftpConfigurationCard
                    }

                    // 3. Compressed Packaging Card
                    archivePackagingCard

                    // 4. Security & Options Card
                    securityOptionsCard

                    // 5. Live Connection Test Banner
                    connectionTestBanner
                }
                .padding(24)
            }
            .frame(maxHeight: 520)

            Divider()

            // MARK: - Footer Actions
            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: headerIcon)
                .font(.title2)
                .foregroundStyle(headerColor)
                .frame(width: 42, height: 42)
                .background(headerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.destinationEditorTargetId == nil ? L10n.t(.remoteDestEditorAddTitle) : L10n.t(.remoteDestEditorEditTitle))
                    .font(.title3.bold())
                Text(L10n.t(.remoteDestEditorSubtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.showRemoteDestinationEditorSheet = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section 1: Overview
    private var destinationOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.remoteDestEditorNameLabel))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TextField(L10n.t(.remoteDestEditorNamePlaceholder), text: nameBinding)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.remoteDestEditorTypeLabel))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    destinationTypeTile(
                        index: 0,
                        title: "S3 Cloud",
                        subtitle: "AWS, B2, R2, MinIO",
                        icon: "icloud.and.arrow.up.fill",
                        accentColor: OtterTheme.oceanicTeal
                    )

                    destinationTypeTile(
                        index: 1,
                        title: "SMB / NAS",
                        subtitle: "Apple SMBfs, Synology",
                        icon: "server.rack",
                        accentColor: OtterTheme.otterAmber
                    )

                    destinationTypeTile(
                        index: 2,
                        title: "WebDAV",
                        subtitle: "Nextcloud, ownCloud",
                        icon: "network",
                        accentColor: OtterTheme.oceanicTeal
                    )

                    destinationTypeTile(
                        index: 3,
                        title: "SFTP / SSH",
                        subtitle: "Secure Remote Shell",
                        icon: "terminal.fill",
                        accentColor: OtterTheme.accentPurple
                    )
                }
            }
        }
        .otterCard(padding: 14)
    }

    private func destinationTypeTile(
        index: Int,
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color
    ) -> some View {
        let isSelected = appState.destinationEditorTypeIndex == index

        return Button {
            withAnimation(OtterTheme.snappySpring) {
                typeIndexBinding.wrappedValue = index
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? accentColor : .secondary)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .secondary : .tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? accentColor : OtterTheme.subtleBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Section 2: S3 Configuration
    private var s3ConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorS3SettingsTitle), systemImage: "cloud.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Text("Zero-Knowledge SigV4")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Quick Presets
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.remoteDestEditorPresetsLabel))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    presetButton(title: "AWS S3", icon: "cube.fill") {
                        appState.destinationEditorS3Endpoint = "https://s3.amazonaws.com"
                        appState.destinationEditorS3Region = "eu-central-1"
                        appState.destinationEditorS3ForcePathStyle = false
                    }

                    presetButton(title: "Backblaze B2", icon: "flame.fill") {
                        appState.destinationEditorS3Endpoint = "https://s3.us-west-004.backblazeb2.com"
                        appState.destinationEditorS3Region = "us-west-004"
                        appState.destinationEditorS3ForcePathStyle = true
                    }

                    presetButton(title: "Cloudflare R2", icon: "bolt.fill") {
                        appState.destinationEditorS3Endpoint = "https://<account-id>.r2.cloudflarestorage.com"
                        appState.destinationEditorS3Region = "auto"
                        appState.destinationEditorS3ForcePathStyle = true
                    }

                    presetButton(title: "MinIO", icon: "server.rack") {
                        appState.destinationEditorS3Endpoint = "http://127.0.0.1:9000"
                        appState.destinationEditorS3Region = "us-east-1"
                        appState.destinationEditorS3ForcePathStyle = true
                    }
                }
            }

            Divider()

            // Endpoint & Bucket
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorEndpointLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorEndpointPlaceholder), text: s3EndpointBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorBucketLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorBucketPlaceholder), text: s3BucketBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Region & Path Prefix
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorRegionLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorRegionPlaceholder), text: s3RegionBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorPrefixLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorPrefixPlaceholder), text: s3PrefixBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Access Key & Secret Access Key
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorAccessKeyLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorAccessKeyPlaceholder), text: s3AccessKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t(.remoteDestEditorSecretKeyLabel))
                            .font(.caption2.bold())
                        Spacer()
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    SecureField(L10n.t(.remoteDestEditorSecretKeyPlaceholder), text: s3SecretAccessKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text(L10n.t(.remoteDestEditorForcePathStyle))
                    .font(.caption)
                Spacer()
                Toggle("", isOn: s3ForcePathStyleBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .otterCard(padding: 14)
    }

    private func presetButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Section 2: SMB Configuration
    private var smbConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorSMBSettingsTitle), systemImage: "server.rack")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.otterAmber)
                Spacer()
                Text("Native Apple SMBfs")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSMBShareLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSMBSharePlaceholder), text: smbShareURLBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSMBSubfolderLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSMBSubfolderPlaceholder), text: smbMountPathBinding)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorSMBUsernameLabel))
                            .font(.caption2.bold())
                        TextField(L10n.t(.remoteDestEditorSMBUsernamePlaceholder), text: smbUsernameBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.remoteDestEditorSMBPasswordLabel))
                                .font(.caption2.bold())
                            Spacer()
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        SecureField(L10n.t(.remoteDestEditorSMBPasswordPlaceholder), text: smbPasswordBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 2: WebDAV Configuration
    private var webdavConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorWebDAVSettingsTitle), systemImage: "network")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Text("RFC 4918 HTTP/HTTPS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorWebDAVURLLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorWebDAVURLPlaceholder), text: webdavURLBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorWebDAVPathLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorWebDAVPathPlaceholder), text: webdavPathBinding)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorWebDAVUsernameLabel))
                            .font(.caption2.bold())
                        TextField(L10n.t(.remoteDestEditorWebDAVUsernamePlaceholder), text: webdavUsernameBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.remoteDestEditorWebDAVPasswordLabel))
                                .font(.caption2.bold())
                            Spacer()
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        SecureField(L10n.t(.remoteDestEditorWebDAVPasswordPlaceholder), text: webdavPasswordBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 2: SFTP Configuration
    private var sftpConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorSFTPSettingsTitle), systemImage: "terminal.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.accentPurple)
                Spacer()
                Text("OpenSSH / SFTP")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorSFTPHostLabel))
                            .font(.caption2.bold())
                        TextField(L10n.t(.remoteDestEditorSFTPHostPlaceholder), text: sftpHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorSFTPPortLabel))
                            .font(.caption2.bold())
                        TextField("22", value: sftpPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 80)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSFTPPathLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSFTPPathPlaceholder), text: sftpPathBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSFTPUsernameLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSFTPUsernamePlaceholder), text: sftpUsernameBinding)
                        .textFieldStyle(.roundedBorder)
                }

                // SFTP Auth Mode Picker & Fields
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.remoteDestEditorSFTPAuthMethodLabel))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Picker("", selection: sftpAuthModeBinding) {
                        Text(L10n.t(.remoteDestEditorSFTPAuthPassword)).tag(0)
                        Text(L10n.t(.remoteDestEditorSFTPAuthKey)).tag(1)
                    }
                    .pickerStyle(.segmented)

                    if appState.destinationEditorSFTPAuthModeIndex == 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.t(.remoteDestEditorSFTPPasswordLabel))
                                    .font(.caption2.bold())
                                Spacer()
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            SecureField(L10n.t(.remoteDestEditorSFTPPasswordPlaceholder), text: sftpPasswordOrKeyBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.t(.remoteDestEditorSFTPAuthKey))
                                    .font(.caption2.bold())
                                Spacer()
                                Image(systemName: "doc.text.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                TextField("~/.ssh/id_ed25519", text: sftpPasswordOrKeyBinding)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.t(.remoteDestEditorSFTPBrowseKeyButton)) {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.showsHiddenFiles = true
                                    panel.message = L10n.t(.remoteDestEditorSFTPSelectKeyTitle)
                                    if panel.runModal() == .OK, let url = panel.url {
                                        appState.destinationEditorSFTPPasswordOrKey = url.path
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 3: Archive Packaging (Tar.Zst / Tar.Gz)
    private var archivePackagingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(OtterTheme.otterAmber)
                        Text(L10n.t(.archivePackagingSectionTitle))
                            .font(.caption.bold())
                    }
                    Text(L10n.t(.archivePackagingToggleDesc))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: archivePackagingBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }

            if appState.destinationEditorArchivePackagingEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.t(.archiveCompressionLevelLabel))
                            .font(.caption2.bold())
                        Spacer()
                        Text(String(format: L10n.t(.archiveCompressionLevelFormat), appState.destinationEditorArchiveCompressionLevel))
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(OtterTheme.otterAmber)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appState.destinationEditorArchiveCompressionLevel) },
                            set: { appState.destinationEditorArchiveCompressionLevel = Int($0) }
                        ),
                        in: 1...9,
                        step: 1
                    )

                    HStack {
                        Text("1: Fast")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("3: Recommended")
                            .font(.caption2.bold())
                            .foregroundStyle(appState.destinationEditorArchiveCompressionLevel == 3 ? OtterTheme.otterAmber : .secondary)
                        Spacer()
                        Text("9: Maximum")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 4: Security & Options
    private var securityOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(OtterTheme.oceanicTeal)
                        Text(L10n.t(.remoteDestEditorEncryptionTitle))
                            .font(.caption.bold())
                    }
                    Text(L10n.t(.remoteDestEditorEncryptionDesc))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: isClientEncryptionBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }

            Divider()

            HStack {
                Text(L10n.t(.remoteDestEditorEnabledToggle))
                    .font(.caption.weight(.medium))
                Spacer(minLength: 12)
                Toggle("", isOn: isEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Live Connection Test Banner
    @ViewBuilder
    private var connectionTestBanner: some View {
        if appState.destinationEditorIsTesting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t(.remoteDestEditorTesting))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if let success = appState.destinationEditorTestSuccessMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OtterTheme.statusSuccess)
                Text(success)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OtterTheme.statusSuccess)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.statusSuccess.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OtterTheme.statusSuccess.opacity(0.3), lineWidth: 1)
            )
        } else if let error = appState.destinationEditorTestErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(OtterTheme.statusError)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(OtterTheme.statusError)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.statusError.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OtterTheme.statusError.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack(spacing: 12) {
            Button {
                appState.testDestinationEditorConnection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                    Text(L10n.t(.remoteDestEditorTestButton))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.destinationEditorIsTesting || !canSave)

            if let targetId = appState.destinationEditorTargetId {
                Button(role: .destructive) {
                    appState.deleteDestinationEditor(destinationId: targetId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(L10n.t(.delete))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()

            Button(L10n.t(.cancel)) {
                appState.showRemoteDestinationEditorSheet = false
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.cancelAction)

            Button(appState.destinationEditorTargetId == nil ? L10n.t(.remoteDestEditorAddButton) : L10n.t(.save)) {
                appState.saveDestinationEditor()
            }
            .buttonStyle(.borderedProminent)
            .tint(OtterTheme.otterAmber)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }
}
