import React, { useState } from 'react';
import Board from './Board';
import './Game.css';

type Player = 'X' | 'O';
type BoardState = (Player | null)[];

const calculateWinner = (squares: BoardState): Player | null => {
  const lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  for (const [a, b, c] of lines) {
    if (squares[a] && squares[a] === squares[b] && squares[a] === squares[c]) {
      return squares[a];
    }
  }
  return null;
};

const Game: React.FC = () => {
  const [board, setBoard] = useState<BoardState>(Array(9).fill(null));
  const [xIsNext, setXIsNext] = useState<boolean>(true);
  
  const winner = calculateWinner(board);
  const isDraw = !winner && board.every(square => square !== null);
  
  const handleClick = (index: number) => {
    if (board[index] || winner) return;
    
    const newBoard = board.slice();
    newBoard[index] = xIsNext ? 'X' : 'O';
    setBoard(newBoard);
    setXIsNext(!xIsNext);
  };

  const resetGame = () => {
    setBoard(Array(9).fill(null));
    setXIsNext(true);
  };

  const status = winner 
    ? `Winner: ${winner}`
    : isDraw 
    ? "It's a draw!"
    : `Next player: ${xIsNext ? 'X' : 'O'}`;

  return (
    <div className="game">
      <div className="game-status">{status}</div>
      <Board squares={board} onClick={handleClick} />
      <button className="reset-button" onClick={resetGame}>
        Reset Game
      </button>
    </div>
  );
};

export default Game; 