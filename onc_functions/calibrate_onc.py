import pandas as pd
import numpy as np
import pickle
from sklearn.metrics import accuracy_score, roc_auc_score, average_precision_score, brier_score_loss
from sklearn.isotonic import IsotonicRegression
    
def print_calibrated_results(y_true, y_pred, y_calibrated):
    '''print scores for pre and post calibration'''
    
    acc = accuracy_score(y_true, np.round(y_pred))
    acc_calibrated = accuracy_score(y_true, np.round(y_calibrated ))
    print ("accuracy - original/calibrated:", acc, "/", acc_calibrated)
        
    auc = roc_auc_score(y_true, y_pred)
    auc_calibrated = roc_auc_score(y_true, y_calibrated)
    print ("ROC AUC - original/calibrated:     ", auc, "/", auc_calibrated)
    
    pr = average_precision_score(y_true, y_pred)
    pr_calibrated = average_precision_score(y_true, y_calibrated )
    print ("avg precision - original/calibrated:", pr, "/", pr_calibrated)
    
    clf_score = brier_score_loss(y_true, y_calibrated, pos_label=1)
    print("\tBrier: %1.3f" % (clf_score))

def calibrate_onc(data, path, model_name):
    """Plot the results of a calibrated model. """
    
    #split test data (subsets 7-9) into new test (7-8)/train(9) sets
    calibration_train_set = data[((data.subset==7)|(data.subset==8))].copy()
    calibration_test_set = data[data.subset==9].copy()

    #define calibration model
    ir = IsotonicRegression(out_of_bounds="clip")
    #fit the model to the probas from the training set
    ir.fit(calibration_train_set.score, calibration_train_set.y )
    
    #evaluate with the test set and save
    calibration_test_set.loc[:,'p_calibrated'] = ir.transform(calibration_test_set.score) 
    
    #calibration_test_set.loc[:,'p_calibrated'] = p_calibrated
    
    #save
    with open(path + 'model_calibrated_' + model_name + '.pickle', 'wb') as picklefile:  
            pickle.dump(ir,picklefile)
    
    with open(path + 'y_calibrated_' + model_name + '.pickle', 'wb') as picklefile:  
            pickle.dump(calibration_test_set, picklefile)
    
    print_calibrated_results(calibration_test_set.y, calibration_test_set.score, calibration_test_set.p_calibrated)
    return calibration_test_set
