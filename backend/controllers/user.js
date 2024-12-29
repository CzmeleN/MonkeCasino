import mongoose from "mongoose";
import User from "../models/user.js";

export const createUser = async (req, res) => {
	const user = new User(req.body);
	
	try {
		await user.save();
		const token = await user.generateAuthToken();
		res.status(201).send({ user, token });
	} catch (e) {
		res.status(400).send(e);
	}
}

export const userLogin = async (req, res) => {
	try {
        const user = await User.findByCredentials(req.body.email, req.body.password)
        const token = await user.generateAuthToken()
        res.send({ user, token })
    } catch (e) {
        res.status(400).send(e)
    }
}

export const userLogout = async (req, res) => {
	try {
        req.user.tokens = req.user.tokens.filter((token) => {
            return token.token !== req.token
        })
        await req.user.save()

        res.send()
    } catch (e) {
        res.status(500).send()
    }
}

export const userLogoutAll = async (req, res) => {
	    try {
        req.user.tokens = []
        await req.user.save()
        res.send()
    } catch (e) {
        res.status(500).send()
    }
}

export const userMe = async (req, res) => {
	res.send(req.user);
}

export const userUpdate = async (req, res) => {
	const updates = Object.keys(req.body)
    const allowedUpdates = ['first_name', 'last_name', 'email', 'password']
    const isValidOperation = updates.every((update) => allowedUpdates.includes(update))

    if (!isValidOperation) {
        return res.status(400).send({ error: 'Invalid updates!' })
    }

    try {
        updates.forEach((update) => req.user[update] = req.body[update])
        await req.user.save()
        res.send(req.user)
    } catch (e) {
        res.status(400).send(e)
    }
}

export const userDelete = async (req, res) => {
	try {
        await req.user.remove()
        res.send(req.user)
    } catch (e) {
        res.status(500).send()
    }
}

/*
// get all users
export const getUsers = async (req, res) => {
    try {
        const users = await User.find({});
        res.status(200).json({success: true, data: users});
    } catch (error) {
        console.log("error in fetching users: ", error);
        res.status(500).json({success: false, message: "Server error"});
    }
}

/*
// get user by id
export const getUser = async (req, res) => {
    const id = req.params.id;

    if(!mongoose.Types.ObjectId.isValid(id))
        return res.status(404).json({success: false, message: "Invalid user id"});

    User.findById(id, (error, user) => {
        if(error) {
            console.log("error in fetching user by id: ", error);
            return res.status(500).json({success: false, message: "Server error"});
        } else {
            res.status(200).json({success: true, data: user});
        }
    })
}

// create user 
export const postUser = async (req, res) => {
    const user = req.body;

    if(!user.first_name){
        return res.status(400).json({success: false, message: "Please provide first name"});
    } else if(!user.last_name){
        return res.status(400).json({success: false, message: "Please provide last name"});
    } else if(!user.email){
        return res.status(400).json({success: false, message: "Please provide email"});
    } else if(!user.password){
        return res.status(400).json({success: false, message: "Please provide password"});
    }

    // email must be unique
    const existingUser = await User.findOne({ email: user.email });
    if(existingUser) {
        return res.status(400).json({success: false, message: "User with this email already exists"});
    }

    const newUser = new User(user);
    try {
        await newUser.save();
        res.status(201).json({success: true, data: newUser});
    } catch (error) {
        console.log("error in creating user: ", error);
        res.status(500).json({success: false, message: "Server error"});
    }
}

// delete user by id
export const deleteUser = async (req, res) => {
    const id = req.params.id;

    if(!mongoose.Types.ObjectId.isValid(id))
        return res.status(404).json({success: false, message: "Invalid user id"});

    try {
        await User.findByIdAndDelete(id);
        res.status(200).json({success: true, message: "User deleted successfully"});
    } catch (error) {
        console.log("error in deleting user: ", error);
        res.status(500).json({success: false, message: "Server error"});
    }
}

// update user by id 
export const updateUser = async (req, res) => {
    const id = req.params.id;
    const user = req.body;

    if(!mongoose.Types.ObjectId.isValid(id))
        return res.status(404).json({success: false, message: "Invalid user id"});

    try {
        const updatedUser = await User.findByIdAndUpdate(id, user, {new: true});
        res.status(200).json({success: true, data: updatedUser});
    } catch (error) {
        console.log("error in updating user: ", error);
        res.status(500).json({success: false, message: "Server error"});
    }
}
*/
