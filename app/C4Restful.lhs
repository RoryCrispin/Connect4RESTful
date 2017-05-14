> {-# LANGUAGE DataKinds #-}
> {-# LANGUAGE TypeFamilies #-}
> {-# LANGUAGE DeriveGeneric #-}
> {-# LANGUAGE TypeOperators #-}

> module Main (main) where
> import Data.Aeson
> import GHC.Generics
> import Network.Wai
> import Servant
> import Network.Wai.Handler.Warp
> import System.Environment

> import Data.List
> import Data.Char
> import Control.Monad
> import Data.Function
> import Network.Wai.Middleware.Cors

  /$$$$$$   /$$$$$$  /$$   /$$ /$$   /$$ /$$$$$$$$  /$$$$$$  /$$$$$$$$       /$$   /$$
 /$$__  $$ /$$__  $$| $$$ | $$| $$$ | $$| $$_____/ /$$__  $$|__  $$__/      | $$  | $$
| $$  \__/| $$  \ $$| $$$$| $$| $$$$| $$| $$      | $$  \__/   | $$         | $$  | $$
| $$      | $$  | $$| $$ $$ $$| $$ $$ $$| $$$$$   | $$         | $$         | $$$$$$$$
| $$      | $$  | $$| $$  $$$$| $$  $$$$| $$__/   | $$         | $$         |_____  $$
| $$    $$| $$  | $$| $$\  $$$| $$\  $$$| $$      | $$    $$   | $$               | $$
|  $$$$$$/|  $$$$$$/| $$ \  $$| $$ \  $$| $$$$$$$$|  $$$$$$/   | $$               | $$
 \______/  \______/ |__/  \__/|__/  \__/|________/ \______/    |__/               |__/


---
*Declarations*
---
The length of a winning combo is declared as a constant here

> c_win 	= 4

Boards are represented as O,X,B where O/X are players and B is 'Blank'

> data PlayerValue = O | B | X deriving (Ord, Eq,Show, Generic)
> instance ToJSON   PlayerValue
> instance FromJSON PlayerValue

> type Row  = [PlayerValue]
> type Board = [Row]

> data BoardState = BoardState
>      { sBoard :: Board, winner :: PlayerValue, errorCode :: Int, difficulty:: Int, playedCol :: Int}  deriving (Eq, Show, Generic)
> instance FromJSON BoardState
> instance ToJSON   BoardState

---
*Web Server Setup*
---

Specify the type of the api - there are four endpoints:
  - getAiMove gets takes a BoardState and calculates a turn for whichever player
    should play next based on the current number of tokens on the board

  - playerMove - takes a board and a column from the BoardState and returns a either
    a new BoarsState with the players move added or the original BoardState with an error code

  - freshBoard /:rows/:cols - pass in the size of the board and this will return a fresh
    gamestate with a board of that size (ie new game)

  - static - host the game html files - not really needed by the API but it's
      convenient not to need a second webserver.

> type BoardAPI = "getAIMove" :> ReqBody '[JSON] BoardState :> Post '[JSON] BoardState
>                      :<|>  "playerMove" :> ReqBody '[JSON] BoardState :> Post '[JSON] BoardState
>                      :<|>  "freshBoard" :> Capture "rows" Int :> Capture "cols" Int :> Get '[JSON] BoardState
>                      :<|>  "static" :> Raw


> boardAPI :: Proxy BoardAPI
> boardAPI = Proxy

> server :: Server BoardAPI
> server = handleMakeAiMove :<|> handleMakePlayerMove :<|> freshBoardHandler :<|> staticHandler

> freshBoardHandler r c = return (BoardState (blankBoard r c) B 0 4 0)
> staticHandler = serveDirectory "static-files"
> handleMakePlayerMove bs = return (makePlayerMove bs)
> handleMakeAiMove bs = return (makeAiMove bs)

Error codes :
        | 0 -> All is fine
        | 1 -> Invalid move
        | 2 -> Full voard

Because of the stateless nature of the system - both AI and Player move handlers
will assume they should place a token for the user with the least tokens on the board
meaning that we don't ever have to keep track of whose turn it is.

AI move handler || if theres an error, just return the original board sent in the req
    otherwise simulate an ai turn and return.

> makeAiMove :: BoardState -> BoardState
> makeAiMove (BoardState b w e d _) = case e of
>                                       0 -> BoardState aiBoard (whoseVictory aiBoard) (isBoardFullToErrorCode aiBoard) d 0
>                                       otherwise -> BoardState b w e d 0
>                                       where aiBoard = (aIGenerateBoard d b (whoseTurn b))

Player move handler || check if the move is valid - if not return the original board
      with error code 1
      else check for victories and return the board.

> makePlayerMove :: BoardState -> BoardState
> makePlayerMove (BoardState b w _ d col) = case evalMove of
>                                     [] -> BoardState b w 1 d col
>                                     otherwise -> BoardState evalMove (whoseVictory evalMove)
>                                              (isBoardFullToErrorCode evalMove) d col
>                                     where evalMove = (isDropTokenValid col (whoseTurn b) b)

Convert isBoardFull :: Bool into an error code we can use in the api.

> isBoardFullToErrorCode :: Board -> Int
> isBoardFullToErrorCode b = if (isBoardFull b) then 2 else 0

> app :: Application
> app = simpleCors (serve boardAPI server)

> main :: IO()
> main = (run 8081) app

Generate the next ai move with MinMaxTeees. The function will return [] if it
can't make any moves, ie someone has already won so in this case; return the
original board.

> aIGenerateBoard :: Int -> Board -> PlayerValue -> Board
> aIGenerateBoard d b p = case aiMove of
>                                [] -> b
>                                otherwise -> aiMove
>                         where aiMove = getNextAIMove p (minMaxTree (assignTreeVictory (generateTree d b p)))

> data Tree a = Node a [Tree a] deriving Show


//===========================================================================\\
                             Board Helper Functions
\\===========================================================================//

Calculate the board size

> getColSize :: Board -> Int
> getColSize b = length (head b)

> getRowSize :: Board -> Int
> getRowSize b = length b

This function creates an empty board of the preset dimensions

> blankRow :: Int -> Row
> blankRow c= take c (repeat B)

> blankBoard :: Int -> Int -> Board
> blankBoard r c = take r (repeat $ blankRow c)

Takes a Board and returns it with the columns as rows (transposed)

> rowsToCols :: Board -> Board
> rowsToCols = transpose

Converts rows into diagonals by offsetting each row with an increasing numbers of
          blank lists to make them line up correctly with rows above and below
          e.g. [X,B][O,O] becomes [[X],[B]][[],[O],[O]] which then zips with to become [[X],[B,O],[O]]
          It use the DiagHelper function to maintain a copy of the original board
          for the so that it can create a list of the correct size.
          Stackoverflow helped with this function :: /question/32465776

> diagonals :: Board -> Board
> diagonals b = diagHelper b b
>               where diagHelper :: Board -> Board -> Board
>                     diagHelper b [] 		=  replicate (max (getColSize b) (getRowSize b)) []
>                     diagHelper b (xs:xss) 	= zipWith (++) (map (:[]) xs ++
>                         replicate (max (getColSize b) (getRowSize b) ) []) ([]: diagHelper b xss)

Gets the specified row from the Board

> getRow :: Int -> Board -> Row
> getRow rNum b = b !! rNum

Updates the row to include the new token by dropping the value in it's place (which will always be a B)

> updateRow :: Int -> Row -> Board -> Board
> updateRow rNum r b = take rNum b ++ [r] ++ drop (rNum + 1) b

Checks if different components of the board is full by checking for the lack of empty spaces

> isRowFull :: Row -> Bool
> isRowFull = not . elem B

> isColFull :: Int -> Board -> Bool
> isColFull colNum b = isRowFull $ getRow colNum (rowsToCols b)

> isBoardFull :: Board -> Bool
> isBoardFull = all id . map isRowFull


Returns the PlayerValue of the current player.
It is determined by checking if the current number of tokens is even or odd

> whoseTurn :: Board -> PlayerValue
> whoseTurn b = if even (totalNumTokens b) then X else O


Inverses the PlayerValue

> notPlayerValue :: PlayerValue -> PlayerValue
> notPlayerValue X = O
> notPlayerValue O = X
> notPlayerValue B = B

Returns the total number of non-blank (X or O) tokens currently on the board

> totalNumTokens :: Board -> Int
> totalNumTokens b = sum $ map length $ map (filter (/=B)) b

---
* Victory Helper Function*
---

Takes a Board and PlayerValue and returns true if that player has a winning combo
    in any direction (c_win length).
      Where
          anyRowVictory = Takes a PlayerValue and a Board returns true if they
              win via *any* row in a the Board

          singleRowVictory = Takes a *single* row and returns true if the given
              PlayerValue has c_win PlayerValue tokens consecutively

          groupPV = Takes a PrlayerValue and row and returns a list of the grouped
              adjacent PlayerValues in that row
              E.g: groupPV X [X,X,X,X,O,X] -> [[X,X,X,X],[X]]

          groupLenth = Takes a list of lists and returns a list of
              each inner list's length
              ie [[X,X,X], [X], [X,X,X,X]] -> [3,1,4]

          checkWinLength Given a list of integers returns True if there is a
              list with length >= c_win (winning length constant)
                This function is used with groupLength to check for a winning line

> hasVictory :: Board -> PlayerValue-> Bool
> hasVictory b p = ((anyRowVictory b p) || (anyRowVictory (rowsToCols b) p) ||
>         (anyRowVictory (diagonals b) p) || (anyRowVictory (diagonals (reverseBoard b)) p))
>                  where
>                        anyRowVictory :: Board -> PlayerValue -> Bool
>                        anyRowVictory b p = or (map (singleRowVictory p) b)

>                        singleRowVictory :: PlayerValue -> Row -> Bool
>                        singleRowVictory p r = checkWinLength( groupLength( groupPV p r))

>                        groupPV :: PlayerValue -> Row -> [Row]
>                        groupPV p r = filter (elem p) (groupBy (==) r)

>                        groupLength :: [[a]] -> [Int]
>                        groupLength = map length

>                        checkWinLength :: [Int] -> Bool
>                        checkWinLength = any (>= c_win)

>                        reverseBoard :: Board -> Board
>                        reverseBoard = map reverse

Takes a board and returns a the a PlayerValue to represent the winner
If there is no winner B will be returned.

> whoseVictory :: Board -> PlayerValue
> whoseVictory b
>           | hasVictory b X = X
>           | hasVictory b O = O
>           | otherwise = B



---
*Dropping Tokens*
---

Drops a token in the column, ensuring it in is in the lowest possible position
(this function is basically gravity) If the last value in the column is a B (empty)
then insert the token there. If it isn't then call the function recursively
with the current column minus the last element. Store this element in a seperate
list and add it back on at the end. This ensures that even the values below where the token is inserted stay the same

> addToken :: PlayerValue -> Row -> Row -> Row
> addToken _ [] _ = []
> addToken p col colTail = if (last col) == B
>                             then (init col) ++ [p] ++ colTail
>                             else addToken p (init col) ((last col) : colTail)


Tranposes the entire board (meaning the columns are now rows) and then drops a
token in the required row (actually a column) and updates the board to include the
updated row. Finally it transposes the board again to return it to it's original state
        Where
              dropTokenAtRow = Drop a token in the specified row
                    Although it seems weird working in rows as tokens are dropped in columns this function is called after
                    transposing the board meaning the 'rows' are actually columns

> dropToken :: Int -> PlayerValue -> Board -> Board
> dropToken cNum p b = rowsToCols $ updateRow cNum (dropTokenAtRow cNum p (rowsToCols b)) (rowsToCols b)
>                      where
>                           dropTokenAtRow :: Int -> PlayerValue -> Board -> Row
>                           dropTokenAtRow rNum p b = addToken p (getRow rNum b) []


Checks if dropping the token at a desired column is valid

> isDropTokenValid :: Int -> PlayerValue -> Board -> Board
> isDropTokenValid cNum p b
> 	| isColFull cNum b = []
> 	| otherwise = dropToken cNum p b

//===========================================================================\\
                                    AI
\\===========================================================================//

Creates a tree which contains all the possible moves from the current board state and the subsequent turns
Only generates to a depth given by the first param - tree (d)epth
        Where
              limitDepth = Stops the tree generating when it reaches a certain depth

> generateTree :: Int -> Board -> PlayerValue -> Tree Board
> generateTree _ [] p = Node [][]
> generateTree d b p = limitDepth d $ Node b [generateTree d bNew (notPlayerValue p) | bNew <- possibleBoards b p ]
>                    where
>                         limitDepth :: Int -> Tree a -> Tree a
>                         limitDepth 0 (Node x _) = Node x []
>                         limitDepth n (Node x ts) = Node x [limitDepth (n-1) t | t <- ts]


Only generates boards that lead to another state, e.g. a full column or a won board returns an empty list meaning it doesn't need to be further expanded

> possibleBoards :: Board -> PlayerValue -> [Board]
> possibleBoards b p = [if anyVictory b then [] else isDropTokenValid x p b | x<- [0..(getColSize b)-1]]
>                       where
>                             anyVictory :: Board -> Bool
>                             anyVictory b = hasVictory b X || hasVictory b O


Creates a tree which contains the board and who wins that board
      Where
          whichVictory = Returns who won that particular board
          boardIsEmpty = Removes the board if it's blank as its useless to us

> assignTreeVictory :: Tree Board -> Tree (Board, PlayerValue)
> assignTreeVictory (Node [] []) = Node ([],B) []
> assignTreeVictory (Node b xs) = Node (b, whoseVictory b) (concat[map assignTreeVictory (filter(boardIsEmpty) xs)])
>                                 where
>                                       boardIsEmpty :: Tree Board -> Bool
>                                       boardIsEmpty (Node [][]) = False
>                                       boardIsEmpty (Node _ _) = True


Creates a minMax tree by propigating up the tree, changing a boards winning player based on its children board
        Where
              restOfTree = the function called recursively on the children nodes until it reaches the leaves
              childrenWinners = the list of players who won the boards below this node

> minMaxTree :: Tree (Board, PlayerValue) -> Tree (Board, PlayerValue)
> minMaxTree (Node (b,p) []) = Node (b,p) []
> minMaxTree (Node (b,p) xs)
>                   | (whoseTurn b) == X = Node (b, (maximum childrenWinners)) restOfTree
>                   | (whoseTurn b) == O = Node (b, (minimum childrenWinners)) restOfTree
>                       where
>                             restOfTree = concat[map minMaxTree xs]
>                             childrenWinners = [p | Node (_,p) _<- restOfTree]


Returns the board which includes the AI's move.
    Where
          getLongestTree = Returns the subtree which has the longest height - this
            makes sure the AI plays for as long as possible and doesn't "give up".
            interestingly, picking the longest tree makes the AI sometimes ignore
            quick wins when it can guarantee a win in the long term.
              ie - not playing a winning move when it could, instead making a move
               that's guaranteed to win down further the line.

          getTreeLength = Returns the length of characters in the tree when it is
              converted to a string - TODO: not the most efficient way to get
              the a rough length but gives an easy estimate of the length

> getNextAIMove :: PlayerValue -> Tree (Board, PlayerValue) -> Board
> getNextAIMove p (Node (b,pV) xs) = let getB (Node (b,_) _) = b in
>                                        case (findIndices (==pV) ([p | Node (_,p) _ <- xs])) of
>                                             [] -> []
>                                             [x] -> getB (xs !! x)
>                                             indxs -> getB (getLongestTree indxs (Node (b,pV) xs))
>                                                 where
>                                                       getLongestTree :: [Int] -> Tree (Board, PlayerValue) -> Tree (Board, PlayerValue)
>                                                       getLongestTree indxs (Node (b,pV) xs) = snd . last $
>                                                           sortBy (compare `on` fst) [getTreeLength $ xs!!indx |  indx <- indxs]

>                                                       getTreeLength :: Tree (Board, PlayerValue) -> (Int, Tree (Board, PlayerValue))
>                                                       getTreeLength tr = (length(show tr), tr)
