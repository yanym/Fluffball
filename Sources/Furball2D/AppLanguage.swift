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

    var imageTurnMenu: String {
        switch self {
        case .simplifiedChinese: "转过来看看我"
        case .english: "Look at Me"
        }
    }

    var imageTurnGreeting: String {
        switch self {
        case .simplifiedChinese: "在看你啦～ 👀"
        case .english: "I’m looking at you! 👀"
        }
    }

    var imageTurnBusy: String {
        switch self {
        case .simplifiedChinese: "等我做完这个动作哦～"
        case .english: "One moment—finishing this move!"
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

    var videoAnimationsMenu: String {
        switch self {
        case .simplifiedChinese: "视频动画（更细腻）"
        case .english: "Video Animations (More Detailed)"
        }
    }

    func videoAnimationsTooltip(capabilities: PetPackCapabilities) -> String {
        switch (self, capabilities.supportsImageMode, capabilities.supportsVideoMode) {
        case (.simplifiedChinese, true, true): "关闭后使用省资源的图片动画模式"
        case (.english, true, true): "Turn off to use the lightweight image animation mode"
        case (.simplifiedChinese, true, false): "此宠物素材包只有图片动画，无法开启视频"
        case (.english, true, false): "This pet pack only includes image animation"
        case (.simplifiedChinese, false, true): "此宠物素材包只有视频动画"
        case (.english, false, true): "This pet pack only includes video animation"
        case (.simplifiedChinese, false, false): "此宠物素材包没有可用的视觉模式"
        case (.english, false, false): "This pet pack has no available visual mode"
        }
    }

    var imageModeEnabled: String {
        switch self {
        case .simplifiedChinese: "切到图片动画啦，轻巧也很可爱～"
        case .english: "Image animation mode—lightweight and cute!"
        }
    }

    var videoModeEnabled: String {
        switch self {
        case .simplifiedChinese: "切回细腻的视频动画啦 ✨"
        case .english: "Detailed video animation is back! ✨"
        }
    }

    var autoBehaviorMenu: String {
        switch self {
        case .simplifiedChinese: "自动作息（睡觉 / 巡游）"
        case .english: "Daily Routine (Sleep / Patrol)"
        }
    }

    var freeRoamMenu: String {
        switch self {
        case .simplifiedChinese: "自由漫游（全桌面）"
        case .english: "Free Roam (Across Desktop)"
        }
    }

    var followCursorMenu: String {
        switch self {
        case .simplifiedChinese: "追随鼠标（全方向走 / 跑）"
        case .english: "Follow Cursor (Move in Any Direction)"
        }
    }

    var imageFacingMenu: String {
        switch self {
        case .simplifiedChinese: "多角度转头"
        case .english: "Multi-Angle Head Turning"
        }
    }

    var crossfadeMenu: String {
        switch self {
        case .simplifiedChinese: "柔和动作过渡"
        case .english: "Smooth Action Transitions"
        }
    }

    var freeRoamStarted: String {
        switch self {
        case .simplifiedChinese: "我去桌面上逛一圈啦！🐾"
        case .english: "I’m off to explore the desktop! 🐾"
        }
    }

    var freeRoamStopped: String {
        switch self {
        case .simplifiedChinese: "逛完啦，我回来陪你～"
        case .english: "All done exploring—I’m back!"
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
            [
                "今天也要陪着你呀 ✨",
                "你忙你的，我负责可爱。",
                "要摸摸我吗？🐾",
                "我来巡逻你的桌面啦！",
                "你一回头就能看见我。",
                "别太累，我会担心的。",
                "发现一只认真工作的你！",
                "尾巴已经替我说喜欢你啦。",
                "今日任务：好好守护你。",
                "需要一点小狗能量吗？",
                "我没有捣乱，是在监督～",
                "嘿，你今天也很厉害！",
                "站得这么乖，有奖励吗？"
            ]
        case (.simplifiedChinese, .sit):
            [
                "我坐好啦，奖励呢？",
                "这里的风景不错汪～",
                "我有在认真陪你哦。",
                "坐等一个香香的摸摸。",
                "我把爪爪放好啦！",
                "这个坐姿能换小饼干吗？",
                "不催你，我就在这里等。",
                "今天也做你的乖宝宝。",
                "耳朵竖好，在听你说哦。",
                "给你一只专注的小狗。",
                "你忙完会陪我玩吗？",
                "看我坐得端不端正？",
                "已就位，请下达摸摸！"
            ]
        case (.simplifiedChinese, .lie):
            [
                "我只是趴着想点事情～",
                "陪你安静一会儿。",
                "地板凉凉的，好舒服。",
                "我把安静分给你一半。",
                "趴一会儿就有力气啦。",
                "你工作，我负责暖场。",
                "我不是懒，是节能模式。",
                "这里刚好能看见你。",
                "爪爪休息，眼睛陪你。",
                "今天也可以慢一点哦。",
                "发呆也是小狗的正事。",
                "要不要一起放空三秒？",
                "软乎乎地陪着你～"
            ]
        case (.simplifiedChinese, .sleep):
            [
                "嘘…梦到小肉干了 💤",
                "再睡五分钟嘛…",
                "呼噜呼噜～别忘了休息。",
                "梦里也在摇尾巴哦。",
                "小狗电量正在恢复中…",
                "梦见你给了我好多零食！",
                "呼呼～今天也很安心。",
                "我闭着眼，也在陪你。",
                "睡醒给你一个大大贴贴。",
                "梦里巡逻，不算偷懒吧？",
                "正在下载甜甜的梦…",
                "鼻子休息，耳朵值班。",
                "如果打呼，请假装没听见～"
            ]
        case (.english, .stand):
            [
                "I’m here to keep you company ✨",
                "You do the work—I’ll be cute.",
                "Got any head pats for me? 🐾",
                "Desktop patrol reporting for duty!",
                "Turn around—I’ll be right here.",
                "Don’t work too hard, okay?",
                "I found one very focused human!",
                "My tail says I really like you.",
                "Today’s mission: look after you.",
                "Need a little puppy energy?",
                "I’m not meddling—I’m supervising.",
                "Hey, you’re doing great today!",
                "Standing nicely earns treats, right?"
            ]
        case (.english, .sit):
            [
                "I’m sitting nicely. Treat?",
                "The view is pretty good from here!",
                "I’m keeping a very close eye on you.",
                "Patiently waiting for a head pat.",
                "Look, I tucked my paws in!",
                "Does this pose earn a biscuit?",
                "No rush. I’ll wait right here.",
                "I’m your good pup today too.",
                "Ears up—I’m listening to you.",
                "One very focused puppy, ready!",
                "Will you play with me when you’re done?",
                "Am I sitting properly enough?",
                "Ready and waiting for cuddles!"
            ]
        case (.english, .lie):
            [
                "Just lying here, thinking dog thoughts.",
                "Let’s enjoy a quiet moment.",
                "This floor is wonderfully cool.",
                "I saved half of this calm for you.",
                "A little rest brings back my zoomies.",
                "You work—I’ll keep things cozy.",
                "I’m not lazy. I’m in power-save mode.",
                "This spot has the perfect view of you.",
                "Paws resting, eyes keeping you company.",
                "It’s okay to take today slowly.",
                "Daydreaming is important puppy work.",
                "Want to do nothing for three seconds?",
                "Just being soft and staying close."
            ]
        case (.english, .sleep):
            [
                "Shh… dreaming of treats 💤",
                "Five more minutes…",
                "Zzz… remember to rest too.",
                "My tail is wagging in my dreams.",
                "Puppy battery recharging…",
                "I dreamed you gave me all the snacks!",
                "Zzz… I feel very safe today.",
                "My eyes are closed, but I’m still here.",
                "Big cuddles when I wake up.",
                "Dream patrol still counts as work, right?",
                "Downloading extra-sweet dreams…",
                "Nose resting. Ears on duty.",
                "If I snore, pretend you didn’t hear."
            ]
        }
    }

    func moodTitle(for mood: PetSpeechBubbleMood) -> String {
        switch (self, mood) {
        case (.simplifiedChinese, .stand): "萌宠日常"
        case (.simplifiedChinese, .sit): "乖巧求摸"
        case (.simplifiedChinese, .lie): "悠闲发呆"
        case (.simplifiedChinese, .sleep): "甜梦呼噜"
        case (.simplifiedChinese, .active): "元气巡视"
        case (.english, .stand): "FURBALL"
        case (.english, .sit): "SWEET"
        case (.english, .lie): "CHILL"
        case (.english, .sleep): "NAP TIME"
        case (.english, .active): "PLAYFUL"
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
