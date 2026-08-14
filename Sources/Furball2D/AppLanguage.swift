import Foundation
import CoreVideo

enum AppLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "appLanguage"

    static var stored: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .simplifiedChinese
        }
        return language
    }

    var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var statusTooltip: String {
        switch self {
        case .simplifiedChinese: "Furball2D 桌面宠物"
        case .english: "Furball2D Desktop Pet"
        }
    }

    var interactMenu: String {
        switch self {
        case .simplifiedChinese: "摸摸它 / 下一动作"
        case .english: "Pet / Next Action"
        }
    }

    var speakMenu: String {
        switch self {
        case .simplifiedChinese: "让它说句话"
        case .english: "Say Something"
        }
    }

    var sleepMenu: String {
        switch self {
        case .simplifiedChinese: "现在去睡觉"
        case .english: "Go to Sleep Now"
        }
    }

    func visibilityMenu(isVisible: Bool) -> String {
        switch (self, isVisible) {
        case (.simplifiedChinese, true): "隐藏宠物"
        case (.simplifiedChinese, false): "显示宠物"
        case (.english, true): "Hide Pet"
        case (.english, false): "Show Pet"
        }
    }

    var passThroughMenu: String {
        switch self {
        case .simplifiedChinese: "完全鼠标穿透"
        case .english: "Click Through Completely"
        }
    }

    var autoBehaviorMenu: String {
        switch self {
        case .simplifiedChinese: "自动活动"
        case .english: "Autonomous Behavior"
        }
    }

    var crossfadeMenu: String {
        switch self {
        case .simplifiedChinese: "柔和动作过渡（MVP）"
        case .english: "Smooth Action Transitions (MVP)"
        }
    }

    var alwaysOnTopMenu: String {
        switch self {
        case .simplifiedChinese: "始终置顶"
        case .english: "Always on Top"
        }
    }

    var sizeMenu: String {
        switch self {
        case .simplifiedChinese: "宠物大小"
        case .english: "Pet Size"
        }
    }

    var sizeTooltip: String {
        switch self {
        case .simplifiedChinese: "连续调整宠物大小"
        case .english: "Continuously adjust the pet size"
        }
    }

    var languageMenu: String { "语言 / Language" }

    var quitMenu: String {
        switch self {
        case .simplifiedChinese: "退出 Furball2D"
        case .english: "Quit Furball2D"
        }
    }

    var sleepConfirmation: String {
        switch self {
        case .simplifiedChinese: "好呀，我去睡啦 💤"
        case .english: "Okay, nap time! 💤"
        }
    }

    var languageChanged: String {
        switch self {
        case .simplifiedChinese: "已经切换成中文啦～"
        case .english: "English mode activated! ✨"
        }
    }

    var problemTitle: String {
        switch self {
        case .simplifiedChinese: "Furball2D 出现问题"
        case .english: "Furball2D Ran Into a Problem"
        }
    }

    var launchFailureTitle: String {
        switch self {
        case .simplifiedChinese: "Furball2D 无法启动"
        case .english: "Furball2D Could Not Start"
        }
    }

    var commandQueueFailure: String {
        switch self {
        case .simplifiedChinese: "无法创建 command queue"
        case .english: "Could not create the Metal command queue"
        }
    }

    var shaderFunctionsMissing: String {
        switch self {
        case .simplifiedChinese: "找不到 Metal shader"
        case .english: "Could not find the Metal shader functions"
        }
    }

    var samplerFailure: String {
        switch self {
        case .simplifiedChinese: "无法创建 sampler"
        case .english: "Could not create the Metal sampler"
        }
    }

    func textureCacheFailure(_ code: CVReturn) -> String {
        switch self {
        case .simplifiedChinese: "无法创建 Core Video texture cache（\(code)）"
        case .english: "Could not create the Core Video texture cache (\(code))"
        }
    }

    func speechMessages(for posture: PetPosture) -> [String] {
        switch (self, posture) {
        case (.simplifiedChinese, .stand):
            ["今天也要陪着你呀 ✨", "你忙你的，我负责可爱。", "要摸摸我吗？🐾"]
        case (.simplifiedChinese, .sit):
            ["我坐好啦，奖励呢？", "这里的风景不错汪～", "我有在认真陪你哦。"]
        case (.simplifiedChinese, .lie):
            ["我只是趴着想点事情～", "陪你安静一会儿。", "地板凉凉的，好舒服。"]
        case (.simplifiedChinese, .sleep):
            ["嘘…梦到小肉干了 💤", "再睡五分钟嘛…", "呼噜呼噜～别忘了休息。"]
        case (.english, .stand):
            ["I’m here to keep you company ✨", "You do the work—I’ll be cute.", "Got any head pats for me? 🐾"]
        case (.english, .sit):
            ["I’m sitting nicely. Treat?", "The view is pretty good from here!", "I’m keeping a very close eye on you."]
        case (.english, .lie):
            ["Just lying here, thinking dog thoughts.", "Let’s enjoy a quiet moment.", "This floor is wonderfully cool."]
        case (.english, .sleep):
            ["Shh… dreaming of treats 💤", "Five more minutes…", "Zzz… remember to rest too."]
        }
    }

    func errorDescription(for error: PetAppError) -> String {
        switch (self, error) {
        case (.simplifiedChinese, .missingAsset(let name)):
            "缺少透明视频素材：\(name)。请先运行 ./Scripts/build-assets.sh。"
        case (.english, .missingAsset(let name)):
            "Missing transparent video asset: \(name). Run ./Scripts/build-assets.sh first."
        case (.simplifiedChinese, .metalUnavailable):
            "当前 Mac 没有可用的 Metal 设备。"
        case (.english, .metalUnavailable):
            "No compatible Metal device is available on this Mac."
        case (.simplifiedChinese, .rendererSetup(let details)):
            "Metal 渲染器初始化失败：\(details)"
        case (.english, .rendererSetup(let details)):
            "The Metal renderer could not be initialized: \(details)"
        }
    }
}
