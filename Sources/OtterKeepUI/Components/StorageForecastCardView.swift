import SwiftUI
import OtterKeepCore

/// Visual card presenting storage depletion forecasting, growth velocity, and low-disk-space quota alerts.
public struct StorageForecastCardView: View {
    public let appState: AppState

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)

                Text(L10n.t(.forecastSectionTitle))
                    .font(.headline)

                Spacer()

                if let report = appState.storageForecastReport {
                    healthBadge(status: report.healthStatus)
                }

                Button {
                    appState.refreshStorageForecast()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh Storage Forecast")
            }

            Text(L10n.t(.forecastSectionDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            // Critical Quota Warning Banner
            if let report = appState.storageForecastReport, report.isQuotaExceeded {
                HStack(spacing: OtterTheme.spacing8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(OtterTheme.statusError)

                    Text(L10n.t(.forecastQuotaExceededBanner))
                        .font(.subheadline.bold())
                        .foregroundStyle(OtterTheme.statusError)
                }
                .padding(OtterTheme.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OtterTheme.statusError.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // Metrics Grid
            if let report = appState.storageForecastReport {
                HStack(alignment: .top, spacing: OtterTheme.spacing16) {
                    // Daily Growth Rate
                    VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                        Text(L10n.t(.forecastDailyGrowthLabel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(report.formattedDailyGrowth)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(OtterTheme.oceanicTeal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 32)

                    // Estimated Depletion
                    VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                        Text(L10n.t(.forecastFullDatePrefix))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let fullDate = report.estimatedFullDate {
                            Text(Self.dateFormatter.string(from: fullDate))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(colorForHealth(report.healthStatus))
                        } else {
                            Text(L10n.t(.forecastSufficientSpace))
                                .font(.subheadline.bold())
                                .foregroundStyle(OtterTheme.statusGreen)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 32)

                    // Days Remaining Pill
                    VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                        Text(L10n.t(.unitDay).capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(report.formattedDepletionText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(colorForHealth(report.healthStatus))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                .padding(OtterTheme.spacing12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: OtterTheme.badgeCornerRadius, style: .continuous))
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n.t(.details))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, OtterTheme.spacing8)
            }
        }
        .otterCard()
        .onAppear {
            if appState.storageForecastReport == nil {
                appState.refreshStorageForecast()
            }
        }
    }

    @ViewBuilder
    private func healthBadge(status: ForecastHealthStatus) -> some View {
        HStack(spacing: 5) {
            Image(systemName: status.sfSymbol)
                .font(.caption2)
            Text(status.rawValue.capitalized)
                .font(.caption2.bold())
        }
        .padding(.horizontal, OtterTheme.spacing8)
        .padding(.vertical, 3)
        .background(colorForHealth(status).opacity(0.15), in: Capsule())
        .foregroundStyle(colorForHealth(status))
    }

    private func colorForHealth(_ status: ForecastHealthStatus) -> Color {
        switch status {
        case .healthy: return OtterTheme.statusGreen
        case .moderate: return OtterTheme.oceanicTeal
        case .warning: return OtterTheme.statusWarning
        case .critical: return OtterTheme.statusError
        }
    }
}
