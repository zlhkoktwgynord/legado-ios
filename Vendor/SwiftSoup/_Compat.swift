// 适配：把 SwiftSoup 源码并入 App 主模块后，模块名限定符失效。
// 这里提供别名/包装，用于命名冲突处引用全局类型和函数。
@usableFromInline typealias HTMLTag = Tag
@usableFromInline typealias HTMLElementRef = Element

/// 避免与实例方法 parse(...) 混淆
@usableFromInline
func soupParse(_ html: String, _ baseUri: String, _ parser: Parser) throws -> Document {
    try parse(html, baseUri, parser)
}
