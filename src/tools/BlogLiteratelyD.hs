import           Text.BlogLiterately
import           Text.BlogLiterately.Diagrams

main :: IO ()
main = blogLiteratelyCustom
  (diagramsInlineXF : diagramsXF : standardTransforms)
