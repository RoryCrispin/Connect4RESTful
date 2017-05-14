// Change this to your host location
var apiLocation = "http://localhost:8081"

// Declare the initial globals
var gameState;
var calculatingMove = false;

$(document).ready(function(){
    newGame();
});

// Request a fresh GameState object from the server,
// taking the board size values from the UI inputs.
function newGame(){
    $.get( apiLocation + '/freshBoard/' + $('#RowCountInput').val() +'/' + $('#ColCountInput').val(), function( data ) {
        gameState = data;
        draw();
    }).fail(function() {
        alert('The server didn\'t respond - maybe you\'ve disconnected?'); // or whatever
    });
}

// Draw the board to the screen. 
function draw(){
    var gameCanvas = '';
    for(var y=0; y < gameState.sBoard.length; y++){
        gameCanvas+='<ul>';
        for(var x=0; x < gameState.sBoard[y].length; x++) {
            gameCanvas+= newButton(x,y);
        }
        gameCanvas+=('</ul>');
    }
    $('.board').empty().append(gameCanvas);
}

// Generates the html for a connect4 'button' and returns as a string
function newButton(xVal,yVal){
    return '<li class="button ' + gameState.sBoard[yVal][xVal] + '" onclick="clickedCol( ' + xVal+ ')"></li>';
}

// Winner ==  B means no one has won the game yet since PlayerValue :: X|O|B
function clickedCol(col){
    if (!calculatingMove){
        calculatingMove = true;
        if (gameState.winner==='B') makeMove(col, false);
        calculatingMove = false;
    } else {console.log('preemptive move from player')}
}

function makeMove(x, aiMove){
    gameState.playedCol=x;
    $.ajax
    ({
        type: 'POST',
        url: apiLocation +'/'+ (aiMove? 'getAIMove' : 'playerMove') ,
        dataType: 'json',
        contentType:'application/json; charset=utf-8',
        async: false,

        data: JSON.stringify(gameState),
        success: function (response) {
            handleResponse(response, aiMove);

            // We a request for the players move first then for the subsequent ai move so that we can give the user
            // instant visual feedback of their move while the computer calculates a response.
            setTimeout(function() { // Introduce a timeout delay so the DOM will update before runnning the second request.
                if (!aiMove && gameState.winner === 'B' && gameState.errorCode===0) makeMove(0, true);
            }, 1);
        },
        error: function () {
            alert('Something went wrong - either you disconnected or the computer took too long to respond (Is the difficulty too hard)');
        }
    });
}


function handleResponse(response, aiMove){
        gameState = response;
        draw();

        switch (response.winner){
            case 'B':
                break;
            case 'X':
                alert('Blue wins!');
                return;
            case 'O':
                alert('Yelllow wins!');
                return;
        }
        switch (response.errorCode){
            case 1:
                alert('Invalid move!');
                break;
            case 2:
                alert('It\'s a draw');
                break;
        }
}


function sliderChanged(v){
    gameState.difficulty = parseInt(v);
}
