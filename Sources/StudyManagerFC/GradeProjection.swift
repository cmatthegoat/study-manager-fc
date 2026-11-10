import SwiftUI

/// Where a subject's marks are heading. The weighted average of the assessments already sat
/// is the only honest base, so the projection says what the final mark becomes if the rest of
/// the weighting is earned at that same average — and, more usefully, what the remaining work
/// has to average to reach each band.
struct GradeProjection: Identifiable {
    let subject: StudySubject
    /// Sum of the weightings already assessed, in percent.
    let satWeighting: Int
    /// Weighted percentage across those assessments.
    let average: Double
    /// Weighting still to be assessed, in percent. Nil weightings count as nothing.
    let remainingWeighting: Int

    var id: String { subject.rawValue }

    var projected: Double { average }

    /// The mark needed across everything still to be assessed to finish on `target`.
    /// Nil when nothing is left, or when the target is already out of reach.
    func needed(for target: Double) -> Double? {
        guard remainingWeighting > 0 else { return nil }
        let needed = (target * 100 - average * Double(satWeighting)) / Double(remainingWeighting)
        guard needed <= 100 else { return nil }
        return max(0, needed)
    }

    static let bands: [(name: String, target: Double)] = [
        ("Band 6", 80),
        ("Band 5", 70),
        ("Band 4", 60)
    ]

    /// One row per subject that has at least one mark and a non-zero weighting.
    static func all(from assessments: [Assessment]) -> [GradeProjection] {
        StudySubject.allCases.compactMap { subject in
            let owned = assessments.filter { $0.subject == subject && $0.weighting > 0 && $0.marksTotal > 0 }
            guard !owned.isEmpty else { return nil }
            let sat = owned.reduce(0) { $0 + $1.weighting }
            guard sat > 0 else { return nil }
            let earned = owned.reduce(0.0) { sum, assessment in
                sum + Double(assessment.marksObtained) / Double(assessment.marksTotal) * 100 * Double(assessment.weighting)
            }
            let average = earned / Double(sat)
            let remaining = max(0, 100 - sat)
            return GradeProjection(
                subject: subject,
                satWeighting: sat,
                average: average,
                remainingWeighting: remaining
            )
        }
        .sorted { $0.average < $1.average }
    }
}

/// The projection card on the Exams tab: one line per subject, so the question "what do I
/// need next?" has an answer without opening a calculator.
struct GradeProjectionCard: View {
    let assessments: [Assessment]

    private var projections: [GradeProjection] { GradeProjection.all(from: assessments) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Grade projection",
                subtitle: projections.isEmpty
                    ? "Log an assessment with a weighting and a mark to see where each subject is heading"
                    : "Weighted from the assessments already sat, and what the rest needs to average",
                symbol: "chart.line.uptrend.xyaxis"
            )

            if !projections.isEmpty {
                HStack(spacing: 6) {
                    Text("SUBJECT").frame(maxWidth: .infinity, alignment: .leading)
                    Text("AVERAGE").frame(width: 64, alignment: .trailing)
                    Text("SAT").frame(width: 44, alignment: .trailing)
                    Text("BAND 4").frame(width: 62, alignment: .trailing)
                    Text("BAND 5").frame(width: 62, alignment: .trailing)
                    Text("BAND 6").frame(width: 62, alignment: .trailing)
                }
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

                VStack(spacing: 0) {
                    ForEach(projections) { projection in
                        HStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(SubjectTheme.color(for: projection.subject))
                                    .frame(width: 7, height: 7)
                                Text(projection.subject.shortName)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(Int(projection.average.rounded()))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(projection.average < 50 ? Color.orange : Color.primary)
                                .frame(width: 64, alignment: .trailing)
                            Text("\(projection.satWeighting)%")
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            ForEach(GradeProjection.bands, id: \.name) { band in
                                Text(neededText(projection, target: band.target))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                        )
                    }
                }
            }

            Text("“Done” means the weighting is fully assessed. A dash means the band can no longer be reached.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Neon.panel.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Neon.border, lineWidth: 1)
        )
    }

    private func neededText(_ projection: GradeProjection, target: Double) -> String {
        guard projection.remainingWeighting > 0 else { return "done" }
        guard let needed = projection.needed(for: target) else { return "—" }
        return "\(Int(needed.rounded()))%"
    }
}
