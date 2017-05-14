# C4Restful
Connect Four with AI implemented as a stateless RESTful server in Haskell with a lighter than air html frontend for show

[Live Demo](http://rorycrispin.co.uk:8081/static/index.html)

![screenshot](https://github.com/RoryCrispin/Connect4RESTful/blob/master/screen.png)

## Building

Building is easy - make sure you have GHC installed and [Stack](https://docs.haskellstack.org/en/stable/README/)
ie 

`$ curl -sSL https://get.haskellstack.org/ | sh`

then clone the repo
~~~~
$ git clone https://github.com/RoryCrispin/Connect4RESTful.git
$ cd Connect4RESTful
~~~~
make sure to set 
and build with Stack 
~~~~
$ stack setup
$ stack build
$ stack exec C4Restful-exe
~~~~
The server should now be running. 
To play - open http://localhost:8081/static/index.html in your browser

# RESTful api
The game logic is all handled by the stateless api. Just send a GameState object to the api and it will return the next move

Get a fresh board
~~~~
$ curl --request GET --url http://localhost:8081/freshBoard/2/2

{"playedCol":0,"errorCode":0,"difficulty":4,"winner":"B","sBoard":[["B","B"],["B","B"]]}%
~~~~
Make a move - set the playedCol field to the column you want to play in.
~~~~
$ curl --request POST \
  --url http://localhost:8081/playerMove \
  --header 'content-type: application/json' \
  --data '{"playedCol":0,"errorCode":0,"difficulty":4,"winner":"B","sBoard":[["B","B"],["B","B"]]}'
  
{"playedCol":0,"errorCode":0,"difficulty":4,"winner":"B","sBoard":[["B","B"],["X","B"]]}%
~~~~
Get the AI's move 
~~~~
$ curl --request POST \
  --url http://localhost:8081/getAIMove \
  --header 'content-type: application/json' \
  --data '{"playedCol":0,"errorCode":0,"difficulty":4,"winner":"B","sBoard":[["B","B"],["X","B"]]}'
  
{"playedCol":0,"errorCode":0,"difficulty":4,"winner":"B","sBoard":[["B","B"],["X","O"]]}%
~~~~

While there is no winner, winner will be "B" - as soon as a winning move is made the field will change to the winning player.

Error codes :
        | 0 -> All is fine
        | 1 -> Invalid move
        | 2 -> Full board

# Warning

If you deliberately try to crash the serer you will succeed - this sort of stability was beyond the project spec - feel free to mess about on your local build of the server but please don't knock the rorycrispin.co.uk server down. 

# Onwards
It would've been nice to be able to include a winning combo length in the GameState so we can set winning conditions on-the-fly but this involved passing the winning combo length int through just about every function in the code. Not pretty! 
I'd like to have written this with monadic state to reduce the messiness of data passing. 

Also, as previously mentioned the server should provide some form of stability protection - simple stuff like checking that the user hasn't requested crazy high board widths or search tree depths (difficulty) would be nice to have. 

The wai  server didn't play ball with CORS headers despite trying. As a public api this would be nice so that in theory any host could make use of this api.



