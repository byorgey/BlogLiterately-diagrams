-----------------------------------------------------------------------------
-- |
-- Module      :  Text.BlogLiterately.Diagrams
-- Copyright   :  (c) Brent Yorgey 2012-2013
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
-- which compiles embedded diagrams code as well as all the standard
-- transforms provided by BlogLiterately.
-----------------------------------------------------------------------------

module Text.BlogLiterately.Diagrams
    ( diagramsXF, diagramsInlineXF
    ) where

import           Safe                        (readMay)
import           System.Directory            (createDirectoryIfMissing)
import           System.FilePath
import           System.IO                   (hPutStrLn, stderr)

import qualified Codec.Picture               as J
import           Data.List                   (find, isPrefixOf)
import           Data.List.Split             (splitOn)
import           Data.Maybe                  (fromMaybe)
import           Diagrams.Backend.Rasterific
import qualified Diagrams.Builder            as DB
import           Diagrams.Prelude            (SizeSpec, V2, centerXY, pad, zero,
                                              (&), (.~))
import           Diagrams.TwoD.Size          (mkSizeSpec2D)
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
diagramsXF = ioTransform renderBlockDiagrams (const True)

renderBlockDiagrams :: BlogLiterately -> Pandoc -> IO Pandoc
renderBlockDiagrams blOpts p = bottomUpM (renderBlockDiagram imgDir imgSize defs) p
  where
    defs = queryWith extractDiaDef p

    imgDir  :: Maybe FilePath
    imgDir = field "imgdir"
    imgSize :: Maybe (SizeSpec V2 Double)
    imgSize = field "imgsize" >>= \s ->
      case splitOn "x" s of
        [w,h] -> Just $ mkSizeSpec2D (readMay w) (readMay h)
        _     -> Nothing

    field f = drop (length f + 1) <$> find ((f++":") `isPrefixOf`) (_xtra blOpts)

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
diagramsInlineXF = ioTransform renderInlineDiagrams (const True)

renderInlineDiagrams :: BlogLiterately -> Pandoc -> IO Pandoc
renderInlineDiagrams _ p = bottomUpM (renderInlineDiagram defs) p
  where
    defs = queryWith extractDiaDef p

extractDiaDef :: Block -> [String]
extractDiaDef (CodeBlock (_, as, _) s)
    = [src | "dia-def" `elem` (maybe id (:) tag) as]
  where
    (tag, src) = unTag s

extractDiaDef _ = []

-- | Given some code with declarations, some attributes, and an
--   expression to render, render it and return the filename of the
--   generated image (or an error message).
renderDiagram :: Bool               -- ^ Apply padding automatically?
              -> [String]           -- ^ Declarations
              -> String             -- ^ Expression to render
              -> SizeSpec V2 Double -- ^ Requested size
              -> Maybe FilePath     -- ^ Directory to save in ("diagrams" if unspecified)
              -> IO (Either String FilePath)
renderDiagram shouldPad decls expr sz mdir = do
    createDirectoryIfMissing True diaDir

    let bopts = DB.mkBuildOpts Rasterific zero (RasterificOptions sz)
                  & DB.snippets .~ decls
                  & DB.imports  .~ ["Diagrams.Backend.Rasterific"]
                  & DB.diaExpr  .~ expr
                  & DB.postProcess .~ (if shouldPad then pad 1.1 . centerXY else id)
                  & DB.decideRegen .~
                      (DB.hashedRegenerate
                        (\_ opts -> opts)
                        diaDir
                      )

    res <- DB.buildDiagram bopts

    case res of
      DB.ParseErr err    -> do
        let errStr = "\nParse error:\n" ++ err
        putErrLn errStr
        return (Left errStr)
      DB.InterpErr ierr  -> do
        let errStr = "\nInterpreter error:\n" ++ DB.ppInterpError ierr
        putErrLn errStr
        return (Left errStr)
      DB.Skipped hash    -> return (Right $ mkFile (DB.hashToHexStr hash))
      DB.OK hash img     -> do
        let imgFile = mkFile (DB.hashToHexStr hash)
        J.savePngImage imgFile (J.ImageRGBA8 img)
        return (Right imgFile)

  where
    diaDir = fromMaybe "diagrams" mdir
    mkFile base = diaDir </> base <.> "png"

renderBlockDiagram :: Maybe FilePath -> Maybe (SizeSpec V2 Double) -> [String] -> Block -> IO Block
renderBlockDiagram ximgDir ximgSize defs c@(CodeBlock attr@(_, cls, fields) s)
    | "dia-def" `elem` classTags = return Null
    | "dia"     `elem` classTags = do
        res <- renderDiagram True (src : defs) "dia" (attrToSize fields) Nothing
        case res of
          Left  err      -> return (CodeBlock attr (s ++ err))
          Right fileName -> do
            case (ximgDir, ximgSize) of
              (Just _, Just sz) -> do
                _ <- renderDiagram True (src : defs) "dia" sz ximgDir
                return ()
              _                 -> return ()
            return $ Para [Image nullAttr [] (fileName, "")]

    | otherwise = return c

  where
    (tag, src)        = unTag s
    classTags         = (maybe id (:) tag) cls


renderBlockDiagram _ _ _ b = return b

renderInlineDiagram :: [String] -> Inline -> IO Inline
renderInlineDiagram defs c@(Code attr@(_, cls, fields) expr)
    | "dia" `elem` cls = do
        res <- renderDiagram False defs expr (attrToSize fields) Nothing
        case res of
          Left err       -> return (Code attr (expr ++ err))
          Right fileName -> return $ Image nullAttr [] (fileName, "")
    | otherwise = return c

renderInlineDiagram _ i = return i

attrToSize :: [(String, String)] -> SizeSpec V2 Double
attrToSize fields
  = mkSizeSpec2D
    (lookup "width" fields >>= readMay)
    (lookup "height" fields >>= readMay)


putErrLn :: String -> IO ()
putErrLn = hPutStrLn stderr
