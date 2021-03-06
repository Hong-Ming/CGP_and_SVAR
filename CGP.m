function CGP(M_est_in,Mode_in)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%      
% MATLAB version 
%     please use version R2019a or later
% Input arguments
%     1. M_est_in: the order of estimated model
%     2. Mode_in: ground true generation method
% Ground True Generation
%     Mode=1: generate ground true using CGP.
%     Mode=2: generate ground true using SVAR.
% Usage
%     This is a polymorphic function, which works for any combination of
%     input and output. 
%     Example of usage : 
%           CGP(In1, In2)
%           CGP([], In2)
%           CGP
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Parameter & Options
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
M_est = 3;          % the order of estimated model
Mode = 1;           % ground true generation method
Max_iter = 30;      % maximum number of iteration
Epsilon = 0.001;    % termination criterion
Skip = true;        % whether to skip step 2
cvx_quiet(true);    % suppress cvx output
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%% Do Not Change Anything Below This Line %%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

rng(10)
% parameter
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
N = 35;             % the number of vertices
K = 100;            % the number of time series
M = 3;              % the order of ground true model
SNR = 25;           % singal to noise ratio
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% polymorphism
if nargin >= 1
    if ~isempty(M_est_in)
        M_est = M_est_in;
    end
end
if nargin >= 2
    if ~isempty(Mode_in)
        Mode = Mode_in;
    end
end

CGP_Model = false;
SVAR_Model = false;
if Mode == 1
   CGP_Model = true;
elseif Mode == 2
   SVAR_Model = true;
else
   error("Choose a Correct Mode")
end

% Define file name
if SVAR_Model
    DataFilename = sprintf('CGPdata%ds.mat',M_est);
elseif CGP_Model
    DataFilename = sprintf('CGPdata%dc.mat',M_est);
end

% Define file path
DataFilePath = fullfile('CGP/',DataFilename);

% generate A
Q = orth(rand(N,N));
Lambda = diag(rand(1,N));
A = Q * Lambda * Q';

for i = 1:N
    for j = i+1:N
        if rand(1)*100 > 2
            A(i,j) = 0;
            A(j,i) = 0;
        else
            A(i,j) = 0.45+A(i,j);
            A(j,i) = A(i,j);
        end
    end
end

for i = 1:N
   A(i,i) = 0.1*A(i,i);
end

% generate c
c = [];
bound = 0.2;
for i = 1:M
    bound = bound - 1/(M+1);
    for j = 0:i
        c(end+1) = -bound + (bound + bound) * rand();
    end
end
c(1) = 0;
c(2) = 1;


% generate x[k]
X = zeros(N,K);
X(:,1:M) = rand(N,M);
if CGP_Model
    fprintf('Generating ground true data using CGP model\n')
    for k = M+1:K
        c_index = 1;
        for i = 1:M
            if k-i == 0 
                break;
            end
            % Compute PA = ci0*I
            PA = c(c_index) * eye(N);
            c_index = c_index + 1;
            % Compute PA = PA + ci1A^1 + ... + cijA^j
            for j = 1:i
                PA = PA + c(c_index) * A^j;
                c_index = c_index + 1;
            end
            % Compute x[k] = x[k] + (ci0*I + ci1A^1 + ... + cijA^j)*x[k-i]
            X(:,k) = X(:,k) + PA * X(:,k-i);
        end
        % add noise to x[k]
        X(:,k) = awgn(X(:,k), SNR, 'measured');
    end
elseif SVAR_Model
    fprintf('Generating ground true data using SVAR model\n')
    % declare A to be a tensor of adjacency matrices
    temp = A;
    A = zeros(N,N,M);
    for k = 1:M
        A(:,:,k) = temp;
        for i = 1:N
            for j = i+1:N
                if A(i,j,k) ~= 0
                   A(i,j,k) = A(i,j,k)/(1.5*randi(10,1));
                   A(j,i,k) = A(i,j,k);
                end
            end
        end
    end
    for k = M+1:K
        for i = 1:M
            if k-i == 0 
                break;
            end
            X(:,k) = X(:,k) + A(:,:,i) * X(:,k-i);
        end
        % add noise to x[k]
        X(:,k) = awgn(X(:,k), SNR, 'measured');
    end
end

% starting optimization

% -------------------------------------------------------------------------
% step 1 : solving matrix polynomial in one shot
% parameter
R = zeros(N,N,M_est);   % tensor of matrix polynomial
c_estimate = 0;
lambda1 = 0.01;
lambda3 = 0.05;
min_error = 1e10;
A_estimate_best = 0;
c_estimate_best = 0;

% pring information
fprintf('Start step 1 :\n');

for iter = 1:Max_iter           % number of iteration
    solve = 0;
    square_error1 = 0;
    square_error2 = 0;
    square_error3 = 0;
    for i = 1:M_est             % for R1 ~ RM
        
        cvx_begin 
                variable Ri(N,N)
                OBJ = cvx(0);              % two norm square error
                CROSS = cvx(0);            % commutatively-enforced term

                % for square error term
                for k = M_est+1:K         % time series x[M] ~ x[K-1], K-M steps predictor
                    temp = X(:,k);
                    % for each Ri
                    for j = 1:M_est
                        if j == i
                            temp = temp - Ri*X(:,k-i);
                        else
                            temp = temp - R(:,:,j)*X(:,k-j);
                        end
                    end
                    OBJ = OBJ + square_pos(norm(temp,2));
                end

                % for commutatively-enforced term
                for j = 1:M_est
                    if i ~= j
                       CROSS = CROSS + square_pos(norm((Ri*R(:,:,j) - R(:,:,j)*Ri),'fro'));
                    end
                end

                % minimum objective function
                if i == 1
                    minimize ((1/2)*OBJ + lambda1*sum(sum(abs(Ri))) + lambda3*CROSS);
                else
                    minimize ((1/2)*OBJ + lambda1*sum(sum(abs(R(:,:,1)))) + lambda3*CROSS);
                end                
        cvx_end
        % computing error
        square_error1 = square_error1 + (1/N^2)*norm(Ri-R(:,:,i),'fro');
        % write back
        R(:,:,i) = Ri;
        % pring information
        fprintf('iter = %d  solving R%d  ',iter,i)
        fprintf('cvx_status = ')
        fprintf(cvx_status)
        fprintf('\n')
        if strcmp(cvx_status,'Solved')
           solve = solve + 1; 
        end
    end
    
    % check convergence
    square_error1 = square_error1 / M_est;
%     if square_error1 < Epsilon
%         fprintf('error = %7.5f < epsilon = %7.5f => Done!',square_error1,Epsilon)
%         fprintf('\n')
%         break;
%     else
%         fprintf('error = %7.5f > epsilon = %7.5f => Continue!',square_error1,Epsilon)
%         fprintf('\n')
%     end
% end

% -------------------------------------------------------------------------
% step 2 : recovering A
% parameter
lambda1 = 0.05;
lambda3 = 0.01;

% pring information
fprintf('Start step 2 :\n');

if Skip
    A_estimate = R(:,:,1);
    fprintf('Skip step 2 ')
    fprintf('\n')
else
    cvx_begin 
        variable A_cvx(N,N)
        CROSS = 0;

        % for commutatively-enforced term
        for i = 2:M_est
            CROSS = CROSS + square_pos(norm((A_cvx*R(:,:,i) - R(:,:,i)*A_cvx),'fro'));
        end

        % minimum objective function
        minimize((1/2)*square_pos(norm(R(:,:,1)-A_cvx,2)) + lambda1*sum(sum(abs(A_cvx))) + lambda3*CROSS);
    cvx_end
    A_estimate = A_cvx;
    % print infromation
    fprintf('cvx_status = ')
    fprintf(cvx_status)
    fprintf('\n')
end
square_error2 = (1/N^2)*norm(A_estimate-R(:,:,1),'fro');

% -------------------------------------------------------------------------
% step 3: estimating c
% parameter
lambda2 = 0.01;

% pring information
fprintf('Start step 3 :\n');

c_pre = c_estimate;
if M_est == 1
    c_estimate = [0;1];
else
    cvx_begin 
        variable c_cvx(((M_est+1)*(M_est+2)/2)-3,1)
        OBJ = 0;

        % for frobenius norm term
        for k = M_est+1:K                 % K-M stop predictor
           Y = X(:,k) - A_estimate*X(:,k-1);
           B = zeros(N,((M_est+1)*(M_est+2)/2)-3);
           col = 1;
           for i = 2:M_est
               for j = 0:i
                   B(:,col) = A_estimate^j * X(:,k-i);
                   col = col + 1;
               end
           end
           OBJ = OBJ + sum((Y-B*c_cvx).^2);
        end

        % minimum objective function
        minimize((1/2)*OBJ + lambda2*sum(abs(c_cvx)));
    cvx_end
    c_estimate = [0;1;c_cvx];
end
square_error3 = (1/length(c_estimate))*norm(c_pre-c_estimate,'fro');

% check convergence
square_error = square_error1 + square_error2 + square_error3;
if Skip
    square_error = (1/2)*square_error;
else
    square_error = (1/3)*square_error;
end

if square_error < min_error
   min_error = square_error;
   A_estimate_best = A_estimate;
   c_estimate_best = c_estimate;
end
if square_error < Epsilon
    fprintf('error = %7.5f < epsilon = %7.5f => Done!',square_error,Epsilon)
    fprintf('\n')
    break;
else
    fprintf('error = %7.5f > epsilon = %7.5f => Continue!',square_error,Epsilon)
    fprintf('\n')
end
end


% print infromation
fprintf('cvx_status = ')
fprintf(cvx_status)
fprintf('\n')
% -------------------------------------------------------------------------

% reconstruction
% -------------------------------------------------------------------------
A_estimate = A_estimate_best;
c_estimate = c_estimate_best;
X_estimate = zeros(N,K);
X_estimate(:,1:M_est) = X(:,1:M_est);
for k = M_est+1:K
    c_index = 1;
    for i = 1:M_est
        % Compute PA = ci0*I
        PA = c_estimate(c_index) * eye(N);
        c_index = c_index + 1;
        % Compute PA = PA + ci1A^1 + ... + cijA^j
        for j = 1:i
            PA = PA + c_estimate(c_index) * A_estimate^j;
            c_index = c_index + 1;
        end
        % Compute x[k] = x[k] + (ci0*I + ci1A^1 + ... + cijA^j)*x[k-i]
        X_estimate(:,k) = X_estimate(:,k) + PA * X_estimate(:,k-i);
    end
end

R1 = R(:,:,1);

save(DataFilePath,'A','R1','A_estimate','X','X_estimate','c','c_estimate','N','K','M','M_est','SNR')

end