module Lazy where

import Control.Monad.Reader
import Data.Bool            (bool)
import Data.Tuple.Extra     (first, second)

import qualified Errors    as Err
import qualified Nameless  as N
import qualified Operators as Op

import Utils

data Expr
  = Integer Int
  | Lambda Expr
  | Apply Expr Expr
  | ParamBound Int
  | LetBound N.LetIndex
  | GlobalBound String Int
  | BinaryOp Op.BinaryOp Expr Expr
  | SingleOp Op.SingleOp Expr
  | Tuple [Expr]
  | NthOf Int Expr
  | Ref Expr
  | Assign Expr Expr
  | Deref Expr
  | If Expr Expr Expr
  | LocalLet Expr Expr
  | LocalBound
  | LetIn [Expr] Expr
  | Error Err.Error
  deriving (Show, Eq)

data Def = Name String Expr deriving (Show, Eq)

data Code =
  Code { definitions :: [Def]
       , entrypoint  :: Expr }
  deriving (Show, Eq)

type Lift = Reader (Int, Int)

liftVars :: N.Expr -> Lift N.Expr
liftVars b@(N.ParamBound i) = bool b (N.ParamBound $ i + 1) <$> asks shouldLift
  where
    shouldLift (n, _) = i >= n
liftVars b@(N.LetBound i) = bool b (N.LetBound $ N.mapLambdaIndex succ i) <$> asks (shouldLift i)
  where
    shouldLift (N.LetIndex lamI letI _) (n, m) = lamI > n || (lamI == n && letI >= m)
liftVars (N.GlobalBound s i)       = return $ N.GlobalBound s (i + 1)
liftVars (N.Integer i)             = return $ N.Integer i
liftVars (N.Lambda x)              = N.Lambda <$> local (first succ) (liftVars x)
liftVars (N.Apply a b)             = N.Apply <$> liftVars a <*> liftVars b
liftVars (N.BinaryOp op a b)       = N.BinaryOp op <$> liftVars a <*> liftVars b
liftVars (N.SingleOp op x)         = N.SingleOp op <$> liftVars x
liftVars (N.Tuple xs)              = N.Tuple <$> mapM liftVars xs
liftVars (N.LetIn ts defs body)    = local (second succ) $ N.LetIn ts <$> mapM liftVars defs <*> liftVars body
liftVars (N.If c t e)              = N.If <$> liftVars c <*> liftVars t <*> liftVars e
liftVars (N.NthOf n i e)           = N.NthOf n i <$> liftVars e
liftVars (N.Error err)             = return $ N.Error err

makeEvaledThunk :: Expr -> Expr
makeEvaledThunk e = Ref $ Tuple [Integer 1, e]

makeThunk :: N.Expr -> Expr
makeThunk e = Ref $ Tuple [Integer 0, code]
  where
    code = Lambda $ NthOf 1 $ Assign (ParamBound 0) updated
    updated = Tuple [Integer 1, lazyExpr $ runReader (liftVars e) (0, 0)]

evalThunk :: Expr -> Expr
evalThunk e = LocalLet (Deref e) $ If cond then_ else_
  where
    cond  = NthOf 0 LocalBound
    then_ = NthOf 1 LocalBound
    else_ = Apply (NthOf 1 LocalBound) e

isValue :: N.Expr -> Bool
isValue N.Integer{}     = True
isValue N.Tuple{}       = True
isValue N.Lambda{}      = True
isValue N.Apply{}       = False
isValue N.ParamBound{}  = False
isValue N.LetBound{}    = False
isValue N.GlobalBound{} = False
isValue N.BinaryOp{}    = False
isValue N.SingleOp{}    = False
isValue N.LetIn{}       = False
isValue N.NthOf{}       = False
isValue N.If{}          = False
isValue N.Error{}       = False

lazify :: N.Expr -> Expr
lazify (N.ParamBound i)    = ParamBound i
lazify (N.GlobalBound s i) = GlobalBound s i
lazify (N.LetBound i)      = LetBound i
lazify x | isValue x       = makeEvaledThunk $ lazyExpr x
         | otherwise       = makeThunk x

lazyExpr :: N.Expr -> Expr
lazyExpr (N.Apply a b)         = Apply (lazyExpr a) (lazify b)
lazyExpr (N.ParamBound i)      = evalThunk (ParamBound i)
lazyExpr (N.LetBound i)        = evalThunk (LetBound i)
lazyExpr (N.GlobalBound s i)   = evalThunk (GlobalBound s i)
lazyExpr (N.Integer i)         = Integer i
lazyExpr (N.BinaryOp op a b)   = BinaryOp op (lazyExpr a) (lazyExpr b)
lazyExpr (N.SingleOp op x)     = SingleOp op (lazyExpr x)
lazyExpr (N.Tuple xs)          = Tuple $ map lazyExpr xs
lazyExpr (N.Lambda body)       = Lambda $ lazyExpr body
lazyExpr (N.LetIn _ defs body) = LetIn (map lazify defs) $ lazyExpr body
lazyExpr (N.If c t e)          = If (lazyExpr c) (lazyExpr t) (lazyExpr e)
lazyExpr (N.NthOf _ i e)       = NthOf i $ lazyExpr e
lazyExpr (N.Error err)         = Error err

lazyDef :: N.NameDef -> Def
lazyDef (N.Name name body) = Name name $ lazify body

lazy :: N.Code -> Code
lazy (N.Code _ _ code) = Code defs entry
  where
    defs = map lazyDef code
    entry = evalThunk (GlobalBound "main" 0)
