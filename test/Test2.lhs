% A Test Post

    [BLOpts]
    profile = wp
    tags = foo,bar
    categories = math,Haskell

This is a test file.

> {-# LANGUAGE NoMonomorphismRestriction #-}
> module Test where
>
> import Diagrams.Prelude

Here's some code:

> foo = square 1 # fc blue

And here is a diagram:

```{.dia width='200'}
import Test

dia :: Diagram B
dia = foo ||| foo
```

Here is another diagram:

```{.dia width='400'}
sierpinski :: Int -> Diagram B
sierpinski 0 = triangle 1
sierpinski n = s' === (s' ||| s') # centerX
  where s' = sierpinski (n-1)

dia = sierpinski 5 # fc black # lw none
```

Hooray!
