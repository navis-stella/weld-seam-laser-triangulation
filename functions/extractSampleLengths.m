
function [TopLength, BotLength] = extractSampleLengths(FileName)
    % Read the lengths of the sample pieces from the file name, e.g. Sample_2119_T30B60.mat
    % (older recordings use _O..U.. instead of _T..B..)
    pattern = '_[TO](\d+)[BU](\d+)';
    tokens = regexp(FileName, pattern, 'tokens');

    if ~isempty(tokens)
        TopLength = str2double(tokens{1}{1});
        BotLength = str2double(tokens{1}{2});
    else
        error('No sample lengths (_T..B..) found in the file name: %s', FileName);
    end
end
