This is a test file.

> {-# LANGUAGE NoMonomorphismRestriction #-}
> module Test where
>
> import Diagrams.Prelude

Here's some code:

> foo = square 1 # fc    blue

And here is a diagram:

```{.dia width='200'}
import Test
dia = foo ||| foo
```

Here's a diagram that uses IO:

```{.dia width='200'}
import Control.Monad.Random
dia :: IO (Diagram Cairo R2)
dia = do
  n <- evalRandIO (getRandomR (1,6))
  return (regPoly n 1 # fc blue)
```

The end.
