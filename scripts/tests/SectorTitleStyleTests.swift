import Foundation

@main
struct SectorTitleStyleTests {
    static func main() throws {
        let sample = #"<script>document.getElementById("3513945").style.color = 'red'; document.getElementById("3513946").style.color = '#2A52BE';</script>"#
        precondition(SectorTitleStyle.colors(in: sample) == [3513945: 0xff0000, 3513946: 0x2a52be])
        let variants = #"document . getElementById ( '42' ) . style . color = '#AbC'; document.getElementById('42').style.color='yellow'; document.getElementById('43').style.color='invalid'; document.getElementById('44').style.color='green';"#
        precondition(SectorTitleStyle.colors(in: variants) == [42: 0xffff00, 44: 0x008000])
        precondition(SectorTitleStyle.colors(in: "plain sector name").isEmpty)
        if CommandLine.arguments.count > 1 {
            let scenario = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            let expected: [Int: UInt32] = [3513945: 0xff0000, 3513946: 0x2a52be,
                3515630: 0xffb841, 3515631: 0x9400d3, 3515632: 0x008000,
                3515635: 0x0047ab, 3515636: 0xff0000, 3515638: 0xffff00]
            precondition(SectorTitleStyle.colors(in: scenario) == expected)
        }
        print("Sector title color regressions passed")
    }
}
