function dp = getNextPixel(Orientation_index)
switch Orientation_index
    case 0
        dp(1) = 1;
        dp(2) = 0;
    case 1
        dp(1) = 1;
        dp(2) = 1;
	case 2
        dp(1) = 0;
		dp(2) = 1;
	case 3
		dp(1) = -1;
		dp(2) = 1;
	case 4
		dp(1) = -1;
		dp(2) = 0;
	case 5
		dp(1) = -1;
		dp(2) = -1;
	case 6
        dp(1) = 0;
        dp(2) = -1;
	case 7
        dp(1) = 1;
        dp(2) = -1;
end