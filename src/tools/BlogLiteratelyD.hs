import           Text.BlogLiterately
import           Text.BlogLiterately.Diagrams

main = blogLiteratelyCustom
  (diagramsInlineXF : diagramsXF : standardTransforms)
