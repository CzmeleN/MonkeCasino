import express from 'express'
import dotenv from 'dotenv'
import path from 'path'
import { connectDB } from './config/db.js'
import userRoutes from './routes/user.js'
import cors from 'cors';

dotenv.config() // load envirenment variables

const app = express();
const PORT = process.env.PORT || 3000;
const __dirname = path.resolve();

// allow to parse json data
app.use(express.json()); 

const corsOptions1 = {
  origin: 'http://localhost:5173',
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
  credentials: true,
  optionsSuccessStatus: 204,
};

const corsOptions2 = {
  origin: 'http://127.0.0.1:8080',
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
  credentials: true,
  optionsSuccessStatus: 204,
};

const corsOptions3 = {
  origin: 'http://localhost:3030',
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
  credentials: true,
  optionsSuccessStatus: 204,
}

app.use((req, res, next) => {
return next();
  const origin = req.header('Origin');

  if (origin === 'http://localhost:5173') {
    cors(corsOptions1)(req, res, next);
  } else if (origin === 'http://127.0.0.1:8080') {
	  cors(corsOptions2)(req, res, next);
  } else if (origin === 'http://localhost:3030') {
      cors(corsOptions3)(req, res, next);  
  } else {
    res.status(403).send('Unauthorised!');
  }
});

// Routes
app.get('/', (req, res) => {
    res.send('Hello')
})
// user routes
app.use('/api/users', userRoutes);

// Server
app.listen(PORT, () => {
    connectDB();
    console.log('Server is running');
});
