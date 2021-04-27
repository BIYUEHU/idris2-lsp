||| Common types and utility funtions for the LSP server implementation.
|||
||| (C) The Idris Community, 2021
module Server.Utils

import Core.Core
import Core.FC
import Core.Name
import Data.Bits
import Data.List
import Data.Strings
import Language.JSON
import Libraries.Data.PosMap
import System.File

||| Gets a specific component of a reference, using the supplied projection.
export
gets : (l : label) -> Ref l a => (a -> b) -> Core b
gets l f = f <$> get l

||| Reads a single header from an LSP message on the supplied file handle.
||| Headers end with the string "\r\n".
export
fGetHeader : (h : File) -> Core (Either FileError String)
fGetHeader handle = do
  Right l <- coreLift $ fGetLine handle
    | Left err => pure $ Left err
  -- TODO: reading up to a string should probably be handled directly by the FFI primitive
  --       or at least in a more efficient way in Idris2
  if isSuffixOf "\r\n" l
     then pure $ Right l
     else (map (l ++)) <$> fGetHeader handle

-- From Language.JSON.Data
private
b16ToHexString : Bits16 -> String
b16ToHexString n =
  case n of
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    15 => "F"
    other => assert_total $
               b16ToHexString (n `shiftR` fromNat 4) ++
               b16ToHexString (n .&. 15)

private
showChar : Char -> String
showChar c
  = case c of
         '\b' => "\\b"
         '\f' => "\\f"
         '\n' => "\\n"
         '\r' => "\\r"
         '\t' => "\\t"
         '\\' => "\\\\"
         '"'  => "\\\""
         c => if isControl c || c >= '\127'
                 then "\\u" ++ b16ToHexString (cast (ord c)) -- quick hack until b16ToHexString is available in Idris2
                 else singleton c

private
showString : String -> String
showString x = "\"" ++ concatMap showChar (unpack x) ++ "\""

export
stringify : JSON -> String
stringify JNull = "null"
stringify (JBoolean x) = if x then "true" else "false"
stringify (JNumber x) = let s = show x in
                            if isSuffixOf ".0" s
                               then substr 0 (length s `minus` 2) s
                               else s
stringify (JString x) = showString x
stringify (JArray xs) = "[" ++ stringifyValues xs ++ "]"
  where
    stringifyValues : List JSON -> String
    stringifyValues [] = ""
    stringifyValues (x :: xs) = stringify x
                             ++ if isNil xs
                                   then ""
                                   else "," ++ stringifyValues xs
stringify (JObject xs) = "{" ++ stringifyProps xs ++ "}"
  where
    stringifyProp : (String, JSON) -> String
    stringifyProp (key, value) = showString key ++ ":" ++ stringify value

    stringifyProps : List (String, JSON) -> String
    stringifyProps [] = ""
    stringifyProps (x :: xs) = stringifyProp x
                            ++ if isNil xs
                                  then ""
                                  else "," ++ stringifyProps xs

export
findInTree : FilePos -> PosMap (NonEmptyFC, Name) -> Maybe Name
findInTree p m = map snd $ head' $ sortBy (\x, y => cmp (measure x) (measure y)) $ searchPos p m
  where
    cmp : FileRange -> FileRange -> Ordering
    cmp ((sr1, sc1), (er1, ec1)) ((sr2, sc2), (er2, ec2)) =
      compare (er1 - sr1, ec1 - sc1) (er2 - sr2, ec2 - sr2)

export
anyAt : (a -> Bool) -> a -> b -> Bool
anyAt p loc _ = p loc
