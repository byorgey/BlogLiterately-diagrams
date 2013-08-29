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

The end.
