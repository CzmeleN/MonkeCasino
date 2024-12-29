import ProtectedRoute from "./ProtectedRoute";
import { lazy } from "react";
import App from "../App";

// import sites
const Greeting = lazy(
    () => import('../pages/Greeting')
);

const Login = lazy(
    () => import('../pages/Login')
);

const Register = lazy(
    () => import('../pages/Register')
);

const ForgotPassword = lazy(
    () => import('../pages/ForgotPassword')
);

const Casino = lazy(
    () => import('../pages/Casino')
);

const Forbidden = lazy(
    () => import('../pages/Forbidden')
);

const NotFound = lazy(
    () => import('../pages/NotFound')
);


const Routes = [
    {
        path: '/',
        element: <App />,
        children: [
            // public routes
            {
                index: true,
                element: <Greeting />
            }, 
            {
                path: '/login', 
                element: <Login />
            },
            {
                path: '/register',
                element: <Register />
            },
            {
                path: '/forgotPassword',
                element: <ForgotPassword />
            },

            // protected routes
            {
                path: '/casino',
                element: <ProtectedRoute />,
                children: [
                    {
                        index: true,
                        element: <Casino />
                    }
                ]
            },
            {
                path: '/api',
                element: <ProtectedRoute />,
                children: [
                    {
                        path: 'users',
                        element: <Forbidden/>
                    }
                ]
            },

            // not found
            {
                path: '*',
                element: <NotFound/>
            }
        ]
    }
]

export default Routes