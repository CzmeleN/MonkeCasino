import { Navigate, Outlet, useLocation } from "react-router-dom";
import { useAuth } from '../context/useAuth'

const ProtectedRoute = () => {
    const location = useLocation();
    const { isLoggedIn } = useAuth();
    return isLoggedIn() ? <Outlet/> : <Navigate to='/login' state={{ fron: location }} replace/>
}

export default ProtectedRoute;