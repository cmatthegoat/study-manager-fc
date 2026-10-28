import Charts
import SwiftUI

/// One bar of an average-marks chart: every marked piece in a subject or topic, pooled.
/// Averages are weighted by marks attempted, so a 20-mark paper counts more than a 5-mark task.
struct MarksAverageRow: Identifiable, Hashable {
    let id: String
    let label: String
    let obtained: Int
    let total: Int
    let pieces: Int

    var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(obtained) / Double(total) * 100).rounded())
    }
}

/// Pools marked work into averages per subject or per topic. Shared by the Exams tab and the
/// Subjects tab so both show the same numbers for the same filter.
enum MarksAverages {
    /// One row per subject.
    static func bySubject(_ sessions: [StudySession]) -> [MarksAverageRow] {
        pool(sessions) { session in
            let name = session.subject?.shortName ?? "Other"
            return (key: name, label: name, subject: nil)
        }
    }

    /// One row per topic. A topic name that appears in two subjects is kept apart and labelled
    /// with its subject, so "Vectors" in Ext 1 and Ext 2 never merge into one bar.
    static func byTopic(_ sessions: [StudySession]) -> [MarksAverageRow] {
        var rows = pool(sessions) { session in
            let topic = session.subtopicName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = topic.isEmpty ? "No topic" : topic
            let subject = session.subject?.shortName ?? "Other"
            return (key: "\(subject)|\(name)", label: name, subject: subject)
        }
        let labelCounts = Dictionary(grouping: rows, by: \.label).mapValues(\.count)
        rows = rows.map { row in
            guard (labelCounts[row.label] ?? 0) > 1,
                  let subject = row.id.components(separatedBy: "|").first
            else { return row }
            return MarksAverageRow(
                id: row.id,
                label: "\(row.label) · \(subject)",
                obtained: row.obtained,
                total: row.total,
                pieces: row.pieces
            )
        }
        return rows.sorted { $0.percentage < $1.percentage }
    }

    private static func pool(
        _ sessions: [StudySession],
        key: (StudySession) -> (key: String, label: String, subject: String?)
    ) -> [MarksAverageRow] {
        var buckets: [String: (label: String, obtained: Int, total: Int, pieces: Int)] = [:]
        for session in sessions {
            guard let obtained = session.marksObtained,
                  let total = session.marksTotal,
                  total > 0 else { continue }
            let grouping = key(session)
            var bucket = buckets[grouping.key] ?? (grouping.label, 0, 0, 0)
            bucket.obtained += obtained
            bucket.total += total
            bucket.pieces += 1
            buckets[grouping.key] = bucket
        }
        return buckets
            .map { key, value in
                MarksAverageRow(
                    id: key,
                    label: value.label,
                    obtained: value.obtained,
                    total: value.total,
                    pieces: value.pieces
                )
            }
            // Weakest first so the chart draws the strongest group at the top.
            .sorted { $0.percentage < $1.percentage }
    }
}

/// Horizontal bars of average percentage, one per subject or topic, coloured by grade band.
struct MarksAverageChart: View {
    let rows: [MarksAverageRow]
    var perRowHeight: CGFloat = 30
    /// Adds the number of marked pieces after each percentage.
    var showsPieceCount = true

    var body: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("Average %", row.percentage),
                y: .value("Group", row.label)
            )
            .foregroundStyle(gradeColor(for: row.percentage).gradient)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                Text(showsPieceCount ? "\(row.percentage)% · \(row.pieces)" : "\(row.percentage)%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label).lineLimit(1)
                    }
                }
            }
        }
        .frame(height: CGFloat(rows.count) * perRowHeight + 24)
    }
}
