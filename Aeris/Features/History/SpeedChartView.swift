import SwiftUI
import Charts

/// The ride speed graph, presented on a Liquid Glass panel.
struct SpeedChartView: View {
    var points: [RidePoint]
    var startDate: Date
    var unit: SpeedUnit

    private var chartData: [RidePoint] {
        guard points.count > 400 else { return points }
        let step = max(1, points.count / 400)
        var sampled = points.enumerated()
            .filter { $0.offset.isMultiple(of: step) }
            .map(\.element)
        if let last = points.last, sampled.last?.t != last.t {
            sampled.append(last)
        }
        return sampled
    }

    private var displayData: [(id: Int, time: Date, speed: Double)] {
        chartData.enumerated().map { index, point in
            (
                id: index,
                time: startDate.addingTimeInterval(point.t),
                speed: unit.speedValue(fromKmh: point.v)
            )
        }
    }

    private var averageKmh: Double {
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0) { $0 + $1.v }
        return total / Double(points.count)
    }

    private var averageDisplaySpeed: Double {
        unit.speedValue(fromKmh: averageKmh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed")
                    .font(.headline)
                Spacer()
                if averageKmh > 0 {
                    Text("avg \(unit.avgSpeedText(fromKmh: averageKmh))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if displayData.count >= 2 {
                chart
            } else {
                Text("Not enough speed data was recorded for this ride.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding(16)
        .glassSurface(in: GlassShape.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speed chart")
    }

    private var chart: some View {
        Chart {
            ForEach(displayData, id: \.id) { item in
                AreaMark(
                    x: .value("Time", item.time),
                    y: .value("Speed", item.speed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", item.time),
                    y: .value("Speed", item.speed)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if averageDisplaySpeed > 0 {
                RuleMark(y: .value("Average", averageDisplaySpeed))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisValueLabel()
            }
        }
        .frame(height: 190)
    }
}
