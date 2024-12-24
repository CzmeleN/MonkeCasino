import mongoose from "mongoose";

const userSchema = mongoose.Schema({
    first_name: {
        type: String,
        required: true
    },
    last_name: {
        type: String,
        required: true
    },
    email: {
        type: String,
        required: true,
        unique: true
    },
    password: {
        type: String,
        required: true
    },
    accoutBallance: {
        type: Number,
        required: true,
        default: 0
    }
}, {
    timestamps: true
});

const User = mongoose.model("User", userSchema);
export default User;