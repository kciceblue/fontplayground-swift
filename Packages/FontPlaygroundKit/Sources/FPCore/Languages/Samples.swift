import Foundation

public enum Samples {
    public static let defaultSample =
        "The quick brown fox jumps over the lazy dog 0123456789\n你好，世界！欢迎使用字体游乐场。\nこんにちは、カタカナとひらがな。\n“Quotes” — dashes… ① → €"
    public static let oldDefaultSample =
        "The quick brown fox jumps over the lazy dog 0123456789\nÄrger Œuvre Ñandú Ωμέγα Привет, мир\n漢字 かな カナ 한글 你好，世界\nمرحبا بالعالم  שלום עולם  नमस्ते\n€ £ ¥ § ¶ → ✓ ☺ ①"
    public static let presets: [(id: String, text: String)] = [
        (
            id: "mixed",
            text:
                "The quick brown fox jumps over the lazy dog 0123456789\n你好，世界！欢迎使用字体游乐场。\nこんにちは、カタカナとひらがな。\n“Quotes” — dashes… ① → €"
        ),
        (
            id: "english",
            text:
                "The quick brown fox jumps over the lazy dog.\nSphinx of black quartz, judge my vow! 0123456789\n“Quotes” ‘apostrophes’ — dashes… (1/2) @ # & € £ %"
        ),
        (id: "chinese_s", text: "你好，世界！欢迎使用字体游乐场。\n天地玄黄，宇宙洪荒。日月盈昃，辰宿列张。\n“引号”——破折号……《书名号》①②③"),
        (id: "chinese_t", text: "你好，世界！歡迎使用字體遊樂場。\n天地玄黃，宇宙洪荒。日月盈昃，辰宿列張。"),
        (id: "japanese", text: "こんにちは、世界！フォントの遊び場へようこそ。\nいろはにほへと ちりぬるを わかよたれそ つねならむ\nカタカナ ひらがな 漢字「かぎかっこ」"),
        (id: "korean", text: "안녕하세요, 세계! 글꼴 놀이터에 오신 것을 환영합니다.\n다람쥐 헌 쳇바퀴에 타고파"),
        (
            id: "all",
            text:
                "The quick brown fox jumps over the lazy dog 0123456789\nÄrger Œuvre Ñandú Ωμέγα Привет, мир\n漢字 かな カナ 한글 你好，世界\nمرحبا بالعالم  שלום עולם  नमस्ते\n€ £ ¥ § ¶ → ✓ ☺ ①"
        ),
    ]
}
