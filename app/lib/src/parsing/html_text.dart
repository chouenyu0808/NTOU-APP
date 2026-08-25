/// 字元類別裡那個是全形空白 U+3000，WebForms 的表格裡到處都是。
/// `&nbsp;`（U+00A0）寫成跳脫序列 —— 它跟一般空白長得一模一樣，
/// 放字面值的話下一個人根本看不出來這行在做什麼。
final RegExp _wsRe = RegExp('[\\s　]+');

/// 壓掉 `&nbsp;`、全形空白、連續空白。
///
/// 不做這件事，「王小明」和「王小明 」會被當成兩個不同的老師，
/// 課表上就會出現兩堂一模一樣的課。
String clean(String text) =>
    text.replaceAll('\u00a0', ' ').replaceAll(_wsRe, ' ').trim();
