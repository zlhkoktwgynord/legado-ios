import XCTest
@testable import LegadoCore

final class RuleTests: XCTestCase {

    private let html = """
    <div class="book">
      <a href="/book/1.html"><h3>书名A</h3></a>
      <span class="author">作者甲</span>
      <p class="intro">简介&nbsp;内容</p>
    </div>
    <div class="book">
      <a href="https://other.com/book/2.html"><h3>书名B</h3></a>
      <span class="author">作者乙</span>
    </div>
    <ul class="list"><li><a href="/c/1.html">第一章</a></li><li><a href="/c/2.html">第二章</a></li></ul>
    """

    func testCSSChain() {
        let rule = AnalyzeRule()
        rule.setContent(html, baseUrl: "https://demo.com/search?q=x")
        // 多个匹配时和阅读一致，按行拼接
        XCTAssertEqual(rule.getString("div.book@a@h3@text"), "书名A\n书名B")
        XCTAssertEqual(rule.getString("div.book.0@a@href", isUrl: true),
                       "https://demo.com/book/1.html")
        XCTAssertEqual(rule.getString("div.book.0@span@text"), "作者甲")
        XCTAssertEqual(rule.getString("div.book@span@text"), "作者甲\n作者乙")
        XCTAssertEqual(rule.getString("div.book@p@text"), "简介 内容")
    }

    func testStringListAndElements() {
        let rule = AnalyzeRule()
        rule.setContent(html, baseUrl: "https://demo.com/")
        let names = rule.getStringList("div.book@h3@text") ?? []
        XCTAssertEqual(names.count, 2)
        let elements = rule.getElements("div.book")
        XCTAssertEqual(elements.count, 2)
        rule.setContent(elements[1])
        XCTAssertEqual(rule.getString("h3@text"), "书名B")
        XCTAssertEqual(rule.getString("a@href", isUrl: true),
                       "https://other.com/book/2.html")
    }

    func testLegadoShorthandSelectors() {
        let page = """
        <div class="bookbox"><div class="book"><h3>书名A</h3><a href="/1.html">阅读</a></div>
        <div class="book"><h3>书名B</h3><a href="/2.html">阅读</a></div></div>
        """
        let rule = AnalyzeRule()
        rule.setContent(page, baseUrl: "https://demo.com/")
        XCTAssertEqual(rule.getElements("class.bookbox").count, 1)
        XCTAssertEqual(rule.getElements("class.bookbox@class.book").count, 2)
        XCTAssertEqual(rule.getString("class.bookbox@class.book.1@h3@text"), "书名B")
        XCTAssertEqual(rule.getElements("tag.div").count, 3)
    }

    func testJSONPath() {
        let json = """
        {"data":[{"name":"甲","id":1},{"name":"乙","id":2}],"total":2}
        """
        let rule = AnalyzeRule()
        rule.setContent(json)
        XCTAssertEqual(rule.getString("$.data[0].name"), "甲")
        XCTAssertEqual(rule.getStringList("$.data[*].name") ?? [], ["甲", "乙"])
        XCTAssertEqual(rule.getString("$.data[-1].name"), "乙")
        XCTAssertEqual(rule.getStringList("$..name") ?? [], ["甲", "乙"])
    }

    func testRegexRule() {
        let rule = AnalyzeRule()
        rule.setContent("作者：张三 著")
        // 选择器为空、只有正则时，直接对整段内容做替换
        XCTAssertEqual(rule.getString("##作者："), "张三 著")
    }

    func testXPathConvert() throws {
        let converted = try XPathBridge.convert("//div[@class='book']//a/@href")
        XCTAssertEqual(converted.selector, "div.book a")
        XCTAssertEqual(converted.lastRule, "href")
        let rule = AnalyzeRule()
        rule.setContent(html, baseUrl: "https://demo.com/")
        XCTAssertEqual(rule.getString("//div[@class='book']//h3/text()", isUrl: false),
                       "书名A\n书名B")
    }

    func testAbsoluteURL() {
        XCTAssertEqual(URLTool.absolute(base: "https://a.com/x/y.html", "/z/1.html"),
                       "https://a.com/z/1.html")
        XCTAssertEqual(URLTool.absolute(base: "https://a.com/x/y.html", "2.html"),
                       "https://a.com/x/2.html")
        XCTAssertEqual(URLTool.absolute(base: "https://a.com/x/y.html", "//cdn.com/a.jpg"),
                       "https://cdn.com/a.jpg")
    }

    func testHTMLToPlain() {
        let text = TextCleaner.htmlToPlain("<div>第一段<br>第二行</div><div>第二段</div>")
        XCTAssertTrue(text.contains("第一段"))
        XCTAssertTrue(text.contains("第二段"))
    }

    func testAnalyzeURL() {
        let plan = AnalyzeURL.build(
            ruleUrl: "https://a.com/search?q={{key}}&page={{page}}",
            source: nil,
            key: "斗破 苍穹",
            page: 2)
        XCTAssertTrue(plan.url.hasPrefix("https://a.com/search?q="))
        XCTAssertTrue(plan.url.contains("page=2"))
        XCTAssertTrue(plan.url.contains("%E6%96%97%E7%A0%B4"))
        XCTAssertEqual(plan.method, "GET")
    }

    func testAnalyzeURLPost() {
        var source = BookSource()
        source.bookSourceUrl = "https://a.com"
        source.header = "{\"User-Agent\":\"test-agent\"}"
        let plan = AnalyzeURL.build(
            ruleUrl: "https://a.com/api/search,{\"method\":\"POST\",\"body\":\"kw={{key}}&p=1\",\"charset\":\"utf-8\"}",
            source: source,
            key: "测试")
        XCTAssertEqual(plan.method, "POST")
        XCTAssertEqual(plan.headers["User-Agent"], "test-agent")
        let body = String(data: plan.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.hasPrefix("kw=%E6%B5%8B%E8%AF%95"))
    }

    func testImportSources() {
        let json = """
        [{"bookSourceName":"测试","bookSourceUrl":"https://a.com",
          "searchUrl":"https://a.com/search?q={{key}}",
          "ruleSearch":{"bookList":"div.book","name":"h3@text","bookUrl":"a@href"}}]
        """
        let sources = SourceImporter.parse(json)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].ruleSearch?.name, "h3@text")
        XCTAssertFalse(sources[0].searchUrl?.isEmpty ?? true)
    }
}
