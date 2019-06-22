module Hoist where

import qualified Closure             as C
import           Control.Monad.State
import qualified Operators           as Op

-- `Call` and `Function` directly correspond to the actual call and function
data Function = Function Int Expr deriving (Show, Eq)

data Expr
  = Integer Int
  | Parameter Int
  | FunctionRef Int
  | NameRef String
  | Call Expr [Expr]
  | BinaryOp Op.BinaryOp Expr Expr
  | SingleOp Op.SingleOp Expr
  | Tuple [Expr]
  | NthOf Int Expr
  | LocalLet Expr Expr
  | LetBound
  | Ref Expr
  | Assign Expr Expr
  | Deref Expr
  | If Expr Expr Expr
  deriving (Show, Eq)

data DefBody
  = Name Expr
  deriving (Show, Eq)

data Def = Def String DefBody
  deriving (Show, Eq)

type Code = [Def]

data Module =
  Module { functions :: [Function]
         , code      :: Code }
  deriving (Show, Eq)

type Hoist = State [Function]

hoistFun :: Expr -> Hoist Expr
hoistFun e = do
  modify (Function 2 e:)
  gets (FunctionRef . pred <$> length)

convertApply :: Expr -> Expr -> Hoist Expr
convertApply a b = return $ LocalLet a $ Call (NthOf 0 LetBound) [NthOf 1 LetBound, b]

hoistExpr :: C.Expr -> Hoist Expr
-- function hoisting
hoistExpr (C.Function e)      = hoistFun =<< hoistExpr e
-- closure calling convention
hoistExpr (C.Apply a b)       = join $ convertApply <$> hoistExpr a <*> hoistExpr b
hoistExpr C.Parameter         = return $ Parameter 1
hoistExpr C.Env               = return $ Parameter 0
-- boring conversion
hoistExpr (C.GlobalName name) = return $ NameRef name
hoistExpr (C.Integer i)       = return $ Integer i
hoistExpr (C.BinaryOp op a b) = BinaryOp op <$> hoistExpr a <*> hoistExpr b
hoistExpr (C.SingleOp op x)   = SingleOp op <$> hoistExpr x
hoistExpr (C.Tuple xs)        = Tuple <$> mapM hoistExpr xs
hoistExpr (C.NthOf i x)       = NthOf i <$> hoistExpr x
hoistExpr (C.Ref x)           = Ref <$> hoistExpr x
hoistExpr (C.Assign a b)      = Assign <$> hoistExpr a <*> hoistExpr b
hoistExpr (C.Deref x)         = Deref <$> hoistExpr x
hoistExpr (C.If c t e)        = If <$> hoistExpr c <*> hoistExpr t <*> hoistExpr e
hoistExpr (C.LocalLet a b)    = LocalLet <$> hoistExpr a <*> hoistExpr b
hoistExpr C.LetBound          = return LetBound

hoistDef :: C.Def -> Hoist Def
hoistDef (C.Def name (C.Name body)) = Def name . Name <$> hoistExpr body

hoistCode :: C.Code -> Hoist Code
hoistCode = mapM hoistDef

hoist :: C.Code -> Module
hoist c = Module { functions = reverse funs, code = c' }
  where
    (c', funs) = runState (hoistCode c) []
