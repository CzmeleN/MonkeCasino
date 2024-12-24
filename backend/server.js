import express from 'express'
import dotenv from 'dotenv'
import path from 'path'
import { connectDB } from './config/db.js'
import userRoutes from './routes/user.js'

dotenv.config() // load envirenment variables

const app = express();
const PORT = process.env.PORT || 3000;
const __dirname = path.resolve();

app.use(express.json()); // allow to parse json data

// Routes
app.get('/', (req, res) => {
    res.send('Hello')
})

// user routes
app.use('/api/users', userRoutes);

// Server
app.listen(PORT, () => {
    connectDB();
    console.log('Server is running on http://localhost:' + PORT);
});
