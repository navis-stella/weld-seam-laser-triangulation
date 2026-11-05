function SummaryRow = saveSeamResults(Result, Strip, ResultsFolder, showFigs)
%% saveSeamResults - save the results of one sample, create plots, return key values
%  Saved in the folder <ResultsFolder>\<Sample>:
%    SeamEvaluation.mat - struct Result (results per image, points, profiles, ROI)
%    LaserStripData.mat - ROI crops of all images (if available)
%    SeamHeight.jpg, SeamWidth.jpg, SampleOffset.jpg
%    Summary_<Sample>.xlsx - key values of this sample
%  SummaryRow: key values of the sample for the summary of all samples

if nargin < 4, showFigs = false; end
target = fullfile(ResultsFolder, Result.Sample);
if ~isfolder(target), mkdir(target); end

save(fullfile(target, 'SeamEvaluation.mat'), 'Result');
if ~isempty(Strip)
    save(fullfile(target, 'LaserStripData.mat'), 'Strip');
end

vis = 'off';  if showFigs, vis = 'on'; end
pos = Result.Position;

f1 = figure('Name', 'Seam height and depth', 'Visible', vis,'Position', [200, 300, 1200, 250]);
    plot(pos, Result.Height, 'b.'); hold on
    plot(pos, Result.Depth, 'r.'); hold off
    grid on; legend('Height', 'Depth');
    xlabel('Position along the seam [°]'); ylabel('Seam height / depth [mm]');
    title(Result.Sample, 'Interpreter', 'none');
exportgraphics(f1, fullfile(target, 'SeamHeight.jpg'));

f2 = figure('Name', 'Seam width', 'Visible', vis, 'Position', [200, 300, 1200, 250]);
    plot(pos, Result.Width, 'm.'); grid on
    xlabel('Position along the seam [°]'); ylabel('Seam width [mm]');
    title(Result.Sample, 'Interpreter', 'none');
exportgraphics(f2, fullfile(target, 'SeamWidth.jpg'));

f3 = figure('Name', 'Sample offset', 'Visible', vis, 'Position', [200, 300, 1200, 250]);
    plot(pos, Result.ContactOffset, 'g.'); grid on
    xlabel('Position along the seam [°]'); ylabel('Offset of the two sample pieces [mm]');
    title(Result.Sample, 'Interpreter', 'none');
exportgraphics(f3, fullfile(target, 'SampleOffset.jpg'));
if ~showFigs, close([f1 f2 f3]); end

%% Key values
n = numel(Result.Height);
SummaryRow.Sample          = string(Result.Sample);
SummaryRow.Images          = n;
SummaryRow.SeamDetected    = nnz(~isnan(Result.Width));
SummaryRow.Height_Median   = median(Result.Height, 'omitnan');
SummaryRow.Height_P5       = prctile(Result.Height, 5);
SummaryRow.Height_P95      = prctile(Result.Height, 95);
SummaryRow.Width_Median    = median(Result.Width, 'omitnan');
SummaryRow.Width_P5        = prctile(Result.Width, 5);
SummaryRow.Width_P95       = prctile(Result.Width, 95);
SummaryRow.Images_with_Height = nnz(~isnan(Result.Height));
SummaryRow.Images_with_Dip    = nnz(~isnan(Result.Depth));
SummaryRow.Depth_Min       = min(Result.Depth, [], 'omitnan');
SummaryRow.Offset_Median   = median(Result.ContactOffset, 'omitnan');
SummaryRow.Offset_Max      = max(Result.ContactOffset, [], 'omitnan');
SummaryRow.Contact_found   = nnz(~isnan(Result.ContactOffset));
SummaryRow.Length_mm       = Result.Length;
SummaryRow.Length_Dev_Pct  = 100 * (Result.Length / Result.NominalLength - 1);

writetable(struct2table(SummaryRow), fullfile(target, ['Summary_' Result.Sample '.xlsx']));
end
