import Foundation

public enum WindowsFonts {
    public struct FaceName: Sendable, Hashable {
        public let family: String
        public let style: String
        public init(family: String, style: String = "Regular") { self.family = family; self.style = style }
    }

    public static let fileTable: [String: [FaceName]] = {
        var result: [String: [FaceName]] = [:]
        func add(_ files: [String], _ families: [String], _ styles: [String]) {
            for (file, style) in zip(files, styles) {
                result[file] = families.map { FaceName(family: $0, style: style) }
            }
        }
        let four = ["Regular", "Bold", "Italic", "Bold Italic"]
        add(["arial.ttf", "arialbd.ttf", "ariali.ttf", "arialbi.ttf"], ["Arial"], four)
        add(["ariblk.ttf"], ["Arial Black"], ["Regular"])
        add(["georgia.ttf", "georgiab.ttf", "georgiai.ttf", "georgiaz.ttf"], ["Georgia"], four)
        add(["times.ttf", "timesbd.ttf", "timesi.ttf", "timesbi.ttf"], ["Times New Roman"], four)
        add(["cour.ttf", "courbd.ttf", "couri.ttf", "courbi.ttf"], ["Courier New"], four)
        add(["verdana.ttf", "verdanab.ttf", "verdanai.ttf", "verdanaz.ttf"], ["Verdana"], four)
        add(["tahoma.ttf", "tahomabd.ttf"], ["Tahoma"], ["Regular", "Bold"])
        add(["trebuc.ttf", "trebucbd.ttf", "trebucit.ttf", "trebucbi.ttf"], ["Trebuchet MS"], four)
        add(["comic.ttf", "comicbd.ttf"], ["Comic Sans MS"], ["Regular", "Bold"])
        add(["impact.ttf"], ["Impact"], ["Regular"])
        add(["micross.ttf"], ["Microsoft Sans Serif"], ["Regular"])
        add(
            ["segoeui.ttf", "segoeuib.ttf", "segoeuii.ttf", "segoeuiz.ttf", "segoeuil.ttf", "seguisb.ttf"],
            ["Segoe UI"], four + ["Light", "Semibold"])
        add(
            ["msyh.ttc", "msyhbd.ttc", "msyhl.ttc"], ["Microsoft YaHei", "Microsoft YaHei UI"],
            ["Regular", "Bold", "Light"])
        add(["simsun.ttc"], ["SimSun", "NSimSun"], ["Regular"])
        add(["simhei.ttf"], ["SimHei"], ["Regular"])
        add(["simkai.ttf"], ["KaiTi"], ["Regular"])
        add(["simfang.ttf"], ["FangSong"], ["Regular"])
        add(["deng.ttf", "dengb.ttf", "dengl.ttf"], ["DengXian"], ["Regular", "Bold", "Light"])
        add(["msjh.ttc", "msjhbd.ttc"], ["Microsoft JhengHei", "Microsoft JhengHei UI"], ["Regular", "Bold"])
        add(["mingliu.ttc"], ["MingLiU", "PMingLiU", "MingLiU_HKSCS"], ["Regular"])
        add(["meiryo.ttc", "meiryob.ttc"], ["Meiryo"], ["Regular", "Bold"])
        add(["msgothic.ttc"], ["MS Gothic", "MS UI Gothic", "MS PGothic"], ["Regular"])
        add(["msmincho.ttc"], ["MS Mincho", "MS PMincho"], ["Regular"])
        add(["yugothr.ttc", "yugothb.ttc", "yugothm.ttc"], ["Yu Gothic"], ["Regular", "Bold", "Medium"])
        add(["yumin.ttf"], ["Yu Mincho"], ["Regular"])
        add(["malgun.ttf", "malgunbd.ttf"], ["Malgun Gothic"], ["Regular", "Bold"])
        add(["gulim.ttc"], ["Gulim", "GulimChe", "Dotum", "DotumChe"], ["Regular"])
        add(["batang.ttc"], ["Batang", "BatangChe", "Gungsuh", "GungsuhChe"], ["Regular"])
        add(["consola.ttf", "consolab.ttf", "consolai.ttf", "consolaz.ttf"], ["Consolas"], four)
        add(["calibri.ttf", "calibrib.ttf", "calibrii.ttf", "calibriz.ttf"], ["Calibri"], four)
        return result
    }()

    public static let equivalents: [String: [String]] = {
        var result: [String: [String]] = [:]
        func add(_ windows: [String], _ mac: [String]) { for family in windows { result[family] = mac } }
        add(["Segoe UI"], ["SF Pro", "Helvetica Neue"])
        add(["Microsoft YaHei", "Microsoft YaHei UI", "DengXian"], ["PingFang SC"])
        add(["Microsoft JhengHei", "Microsoft JhengHei UI"], ["PingFang TC"])
        add(["SimSun", "NSimSun"], ["Songti SC"])
        add(["MingLiU", "PMingLiU", "MingLiU_HKSCS"], ["Songti TC"])
        add(["SimHei"], ["Heiti SC", "STHeiti"])
        add(["KaiTi"], ["Kaiti SC"])
        add(["FangSong"], ["STFangsong"])
        add(["Meiryo", "Yu Gothic", "MS Gothic", "MS UI Gothic", "MS PGothic"], ["Hiragino Sans", "YuGothic"])
        add(["MS Mincho", "MS PMincho", "Yu Mincho"], ["Hiragino Mincho ProN", "YuMincho"])
        add(["Malgun Gothic", "Gulim", "GulimChe", "Dotum", "DotumChe"], ["Apple SD Gothic Neo"])
        add(["Batang", "BatangChe", "Gungsuh", "GungsuhChe"], ["AppleMyungjo"])
        add(["Consolas"], ["SF Mono", "Menlo"])
        return result
    }()

    public static func faceName(forFile basename: String, index: Int) -> FaceName? {
        guard let names = fileTable[basename.lowercased()] else { return nil }
        if names.count == 1 { return names[0] }
        return names.indices.contains(index) ? names[index] : nil
    }

    public static func replacements(forFamily family: String, in catalog: FaceCatalog, main: FaceRecord?)
        -> [FaceRecord]
    {
        Array(
            (equivalents[family] ?? []).compactMap { family in
                // CRIT-3: private copies in Office are not general-purpose replacement suggestions.
                Smart.defaultFace(
                    catalog.faces(family: family).filter { !FolderCheck.insideApplicationBundle($0.path) }, main: main)
            }.prefix(2))
    }
}
