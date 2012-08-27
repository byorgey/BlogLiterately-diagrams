-----------------------------------------------------------------------------
-- |
-- Module      :  Text.BlogLiterately.Diagrams
-- Copyright   :  (c) Brent Yorgey 2012
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  Brent Yorgey <byorgey@gmail.com>
--
-- Custom transformation passes for the @BlogLiterately@ blog-writing
-- tool (<http://hackage.haskell.org/package/BlogLiterately>),
-- allowing inclusion of inline code using the @diagrams@ framework
-- (<http://projects.haskell.org/diagrams>) which are compiled into
-- images.  See "Text.BlogLiterately.Run" for more information.
--
-- Note that this package provides an executable, @BlogLiteratelyD@,
-- which uses the transformation pipeline
--
-- > (diagramsInlineXF : diagramsXF : centerImagesXF : standardTransforms)
-----------------------------------------------------------------------------

module Text.BlogLiterately.Diagrams
    ( diagramsXF, diagramsInlineXF
    ) where

import           Control.Arrow
import           Data.List        (isPrefixOf)
import qualified Data.Map as M
import           Safe             (readMay, headDef)
import           System.FilePath
import           System.IO        (stderr, hPutStrLn)

import           Diagrams.Backend.Cairo
import           Diagrams.Backend.Cairo.Internal
import           Diagrams.Builder
import           Diagrams.Prelude (R2, zeroV)
import           Diagrams.TwoD.Size ( SizeSpec2D(Dims), mkSizeSpec )
import           Text.BlogLiterately
import           Text.Pandoc

-- | Transform a blog post by looking for code blocks with class
--   @dia@, and replacing them with images generated by evaluating the
--   identifier @dia@ and rendering the resulting diagram.  In
--   addition, blocks with class @dia-def@ are collected (and deleted
--   from the output) and provided as additional definitions that will
--   be in scope during evaluation of all @dia@ blocks.
--
--   Be sure to use this transform /before/ the standard
--   'Text.BlogLiterately.Transform.highlightXF' transform, /i.e./
--   with the 'Text.BlogLiterately.Run.blogLiteratelyCustom' function.
--   For example,
--
--   > main = blogLiteratelyCustom (diagramsXF : standardTransforms)
--
--   It also works well in conjunction with
--   'Text.BlogLiterately.Transform.centerImagesXF' (which, of course,
--   should be placed after @diagramsXF@ in the pipeline).  This
--   package provides an executable @BlogLiteratelyD@ which
--   includes @diagramsInlineXF@, @diagramsXF@, and @centerImagesXF@.
diagramsXF :: Transform
diagramsXF = Transform (\bl -> Kleisli $ renderBlockDiagrams bl) (const True)

renderBlockDiagrams :: BlogLiterately -> Pandoc -> IO Pandoc
renderBlockDiagrams _ p = bottomUpM (renderBlockDiagram defs) p
  where
    defs = queryWith extractDiaDef p

-- | Transform a blog post by looking for /inline/ code snippets with
--   class @dia@, and replacing them with images generated by
--   evaluating the contents of each code snippet as a Haskell
--   expression representing a diagram.  Any code blocks with class
--   @dia-def@ will be in scope for the evaluation of these
--   expressions (such code blocks are unaffected).
--
--   Because @diagramsXF@ and @diagramsInlineXF@ both use blocks with
--   class @dia-def@, but @diagramsInlineXF@ leaves them alone whereas
--   @diagramsXF@ deletes them, @diagramsInlineXF@ must be placed
--   before @diagramsXF@ in the pipeline.
diagramsInlineXF :: Transform
diagramsInlineXF = Transform (\bl -> Kleisli $ renderInlineDiagrams bl) (const True)

renderInlineDiagrams :: BlogLiterately -> Pandoc -> IO Pandoc
renderInlineDiagrams _ p = bottomUpM (renderInlineDiagram defs) p
  where
    defs = queryWith extractDiaDef p

extractDiaDef :: Block -> [String]
extractDiaDef (CodeBlock (_, as, _) s)
    = [src | "dia-def" `elem` (maybe id (:) tag) as]
  where
    (tag, src) = unTag s

extractDiaDef b = []

diaDir = "diagrams"  -- XXX make this configurable

-- | Given some code with declarations, some attributes, and an
--   expression to render, render it and return the filename of the
--   generated image (or an error message).
renderDiagram :: [String]     -- ^ Declarations
              -> String       -- ^ Expression to render
              -> Attr         -- ^ Code attributes
              -> IO (Either String FilePath)
renderDiagram decls expr attr@(ident, cls, fields) = do
    res <- buildDiagram
           Cairo
           (zeroV :: R2)
           (CairoOptions "default.png" size PNG)
           decls
           (expr ++ " {- " ++ show attr ++ " -}")
             -- the above hack is to make sure that changing
             -- attributes results in the diagram being recompiled.
           []
           ["Diagrams.Backend.Cairo"]
           (hashedRegenerate
             (\hash opts -> opts { cairoFileName = mkFile hash })
             diaDir
           )
    case res of
      ParseErr err    -> do
        let errStr = "\nParse error:\n" ++ err
        putErrLn errStr
        return (Left errStr)
      InterpErr ierr  -> do
        let errStr = "\nInterpreter error:\n" ++ ppInterpError ierr
        putErrLn errStr
        return (Left errStr)
      Skipped hash    ->        return (Right $ mkFile hash)
      OK hash (act,_) -> act >> return (Right $ mkFile hash)

  where
    size        = mkSizeSpec
                    (lookup "width" fields >>= readMay)
                    (lookup "height" fields >>= readMay)
    mkFile base = diaDir </> base <.> "png"

renderBlockDiagram :: [String] -> Block -> IO Block
renderBlockDiagram defs c@(CodeBlock attr@(_, cls, _) s)
    | "dia-def" `elem` tags = return Null
    | "dia"     `elem` tags = do
        res <- renderDiagram (src : defs) "pad 1.1 dia" attr
        case res of
          Left  err  -> return (CodeBlock attr (s ++ err))
          Right file -> return $ Para [Image [] (file, "")]

    | otherwise = return c

  where
    (tag, src)        = unTag s
    tags              = (maybe id (:) tag) cls

renderBlockDiagram _ b = return b

renderInlineDiagram :: [String] -> Inline -> IO Inline
renderInlineDiagram defs c@(Code attr@(_, cls, _) expr)
    | "dia" `elem` cls = do
        res <- renderDiagram defs expr attr
        case res of
          Left err   -> return (Code attr (expr ++ err))
          Right file -> return $ Image [] (file, "")
    | otherwise = return c

renderInlineDiagram _ i = return i

putErrLn :: String -> IO ()
putErrLn = hPutStrLn stderr