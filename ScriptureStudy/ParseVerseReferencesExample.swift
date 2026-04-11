
let chapterText = "Some text... as we see in Ps. 22:1; 27:9 and more text..."

let references = parseVerseReferences(text: chapterText)

var processedText = chapterText

for reference in references {
    let verseUrl = "scripture://\(reference.book)/\(reference.chapter)/\(reference.verse)"
    let linkTag = "<a href=\"\(verseUrl)\">\(reference.book) \(reference.chapter):\(reference.verse)</a>"
    
    processedText = processedText.replacingOccurrences(of: "\(reference.book) \(reference.chapter):\(reference.verse)", with: linkTag)
}

// processedText will now contain:
"Some text... as we see in <a href=\"scripture://Ps/22/1\">Ps. 22:1</a>; <a href=\"scripture://Ps/27/9\">27:9</a> and more text..."
