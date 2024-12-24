import express from 'express';
import { getUser, getUsers, postUser, deleteUser, updateUser } from '../controllers/user.js';

const router = express.Router();

router.get('/', getUsers);

router.get('/:id', getUser);

router.post('/', postUser);

router.delete('/:id', deleteUser);

router.put('/:id', updateUser);

export default router;