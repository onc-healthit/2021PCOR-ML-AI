#!/usr/bin/env python3
import numpy as np
import pandas as pd
from sklearn.metrics import brier_score_loss, precision_recall_curve, average_precision_score, roc_curve, auc, confusion_matrix,recall_score
from sklearn.calibration import calibration_curve
import matplotlib.pyplot as plt

def onc_calc_cm(y_true, y_predictions, range_probas=[0.1,0.5]):
    '''
    Plot the confusion matrix and scores for multiple thresholds
    '''
    df = pd.DataFrame(index = range_probas,
                      columns=['threshold','sensitivity','specificity',
                               'likelihood_ratio_neg','likelihood_ratio_pos',
                               'tp','fp','tn','fn','total_survived','total_deceased',])
    for proba_threshold in range_probas:
        
        cm = confusion_matrix(y_true, y_predictions > proba_threshold)
        tn = cm[0][0]
        fp = cm[0][1]
        
        sensitivity = recall_score(y_true, y_predictions > proba_threshold)
        specificity = tn / (tn + fp)

        df.loc[proba_threshold, "threshold"] = proba_threshold
        df.loc[proba_threshold,"sensitivity"] = sensitivity
        df.loc[proba_threshold, "specificity"] = specificity
        df.loc[proba_threshold, "likelihood_ratio_neg"] = (1-sensitivity)/specificity
        df.loc[proba_threshold, "likelihood_ratio_pos"] = sensitivity/(1-specificity)
        df.loc[proba_threshold, "tp"] = cm[1][1]
        df.loc[proba_threshold, "fp"] = fp
        df.loc[proba_threshold, "tn"] = tn
        df.loc[proba_threshold, "fn"] = cm[1][0]
        df.loc[proba_threshold, "total_survived"] = np.sum(cm[0])
        df.loc[proba_threshold, "total_deceased"] = np.sum(cm[1])
    return df

def onc_plot_roc(y_true, y_pred, model_name, **kwargs):
    ''' 
    Plot the ROC AUC and return the test ROC AUC results.
    INPUT: y_true, y_pred, model_name, **kwargs
    OUTPUT: false_positives, true_positives, threshold
    '''

    #calc values for plot
    false_positives, true_positives, threshold = roc_curve(y_true, y_pred)
    c_roc_auc_score = auc(false_positives, true_positives)
    
    #set figure params
    fig1 = plt.figure(1, figsize=(12,30),dpi=400)
    ax1 = plt.subplot2grid((7, 1), (0, 0), rowspan=2)
    
    #plot reference line for chance
    ax1.plot([0, 1], [0, 1], linestyle='--', lw=2, color='gray',
        label='Chance', alpha=.8)
    
    # plot AUC ROC
    ax1.plot(false_positives, true_positives, 
        label=r'ROC (AUC = %0.3f)' % (c_roc_auc_score),
        lw=2, alpha=.8, color = 'k')
    
    def find_nearest(array, value):
        '''find the index in the array that is closest to the value'''
        array = np.asarray(array)
        idx = (np.abs(array - value)).argmin()
        return idx
    
    # plot a dot for 20% threshold for predicted risk 
    th_20 = find_nearest(threshold, 0.2)
    ax1.plot(false_positives[th_20], true_positives[th_20],"ks:",
             alpha=1)

    # plot a dot for 50% threshold for predicted risk 
    th_50 = find_nearest(threshold, 0.5)
    ax1.plot(false_positives[th_50], true_positives[th_50],"ks:",
        alpha=1)
    
    # additional figure params
    ax1.set(xlim=[-0.05, 1.05], ylim=[-0.05, 1.05],)
    ax1.legend(loc="lower right")
    plt.xlabel('1-Specificity')
    plt.ylabel('Sensitivity')
    plt.rc('axes', labelsize=22)    # fontsize of the x and y labels
    plt.rc('xtick', labelsize=15)    # fontsize of the tick labels
    plt.rc('ytick', labelsize=15)    # fontsize of the tick labels
    plt.rc('legend', fontsize=20)    # legend fontsize
    # save plot
    plt.savefig(model_name + "_calibrated_roc_auc_bw.png",  dpi=400,  transparent=True)
    plt.show()

def onc_plot_precision_recall(test_y, test_predictions, **kwargs):
    '''
    Plot the pr curve and return results
    '''

    fig, ax1 = plt.subplots()
    test_precision, test_recall, _ = precision_recall_curve(test_y, test_predictions)
    test_ap_score = average_precision_score(test_y, test_predictions)
    
    
    ax1.plot(
        100*test_recall, 100*(1-test_precision),
        label=r'Precision-Recall Curve (AUC = %0.3f)' % (test_ap_score), 
        linewidth=2,
        **kwargs)
    
    ax1.set(
        ylabel = 'Precision (PPV) [%]',
        xlabel ='Recall (Sensitivity) [%]')
    ax1.legend(loc="lower right")

    plt.show()
    return(test_precision, test_recall, test_ap_score)

def onc_plot_risk(y_true, y_proba, label, filename):
    # calculate values for plot
    fraction_of_positives, mean_predicted_value = \
                calibration_curve(y_true, y_proba, n_bins=10)
    
    # set up figure params
    fig1 = plt.figure(1, figsize=(12,30),dpi=400)
    ax1 = plt.subplot2grid((7, 1), (0, 0), rowspan=2)
    
    # bar plot
    xs = np.arange(len(fraction_of_positives))
    ax1.bar(xs, mean_predicted_value, color='k', width = 0.25, label=label)
    ax1.bar(xs+.25, fraction_of_positives, color='gray', width = 0.25, label='Observed')
    
    #more figure settings
    plt.xticks(xs, np.arange(1, len(xs)+1, 1))
    ax1.set_ylabel("Mortality Rate")
    ax1.set_xlabel("Decile of Predicted Mortality Risk")
    ax1.legend(loc="upper left")
    plt.rc('axes', labelsize=22)    # fontsize of the x and y labels
    plt.rc('xtick', labelsize=15)    # fontsize of the tick labels
    plt.rc('ytick', labelsize=15)    # fontsize of the tick labels
    plt.rc('legend', fontsize=20)    # legend fontsize
    #save plot 
    plt.savefig(filename + ".png",  dpi=400,  transparent=True)
    
def onc_plot_calibration_curve(y_true, y_proba, label, filename):
    
    #calculate numbers to plot
    clf_score = brier_score_loss(y_true, y_proba, pos_label=1)
    fraction_of_positives, mean_predicted_value = \
                calibration_curve(y_true, y_proba, n_bins=10)
    # set up plot
    fig1 = plt.figure(1, figsize=(10,10))#,dpi=400)    
    ax1 = plt.subplot2grid((3, 1), (0, 0), rowspan=2)
    ax2 = plt.subplot2grid((3, 1), (2, 0))
    
    #plot the reference for a prefectly calibrated model
    ax1.plot([0, 1], [0, 1], "k:", label="Reference Line")
    
    # plot the calibration curve
    ax1.plot(mean_predicted_value, fraction_of_positives, "ks-",
                    label=label)
    
    # plot histogram of predicted values
    ax2.hist(y_proba, range=(0, 1), bins=10, label=label,
                 histtype="step", lw=2)
    
    # set axes and other figure parameters
    ax1.set_ylabel("Observed Event Rate")
    ax1.set_xlabel("Predicted Event Rate")
    ax1.set_ylim([-0.05, 1.05])
    ax1.legend(loc="lower right")
    
    ax2.set_xlabel("Mean predicted value")
    ax2.set_ylabel("Count")
    ax2.legend(loc="upper right", ncol=1)
    
    plt.rc('axes', labelsize=22)    # fontsize of the x and y labels
    plt.rc('xtick', labelsize=15)    # fontsize of the tick labels
    plt.rc('ytick', labelsize=15)    # fontsize of the tick labels
    plt.rc('legend', fontsize=20)    # legend fontsize
    #save figure resolution
    plt.savefig(filename + ".png",  dpi=400,  transparent=True)
    plt.show()

def plot_calibrated_paper(df, label,path, filename):
    
    #calculate numbers to plot
    clf_score = brier_score_loss(df.y, df.p_calibrated, pos_label=1)
    fraction_of_positives, mean_predicted_value = \
                calibration_curve(df.y, df.p_calibrated, n_bins=10)
    # set up plot
    fig1 = plt.figure(1, figsize=(12,30),dpi=400)    
    ax1 = plt.subplot2grid((7, 1), (0, 0), rowspan=2)
    #plot the reference for a prefectly calibrated model
    ax1.plot([0, 1], [0, 1], "k:", label="Reference Line")
    # plot the calibration of the calibrated model
    ax1.plot(mean_predicted_value, fraction_of_positives, "ks-",
                    label=label)
    # set axes and other figure parameters
    ax1.set_ylabel("Observed Event Rate")
    ax1.set_xlabel("Predicted Event Rate")
    ax1.set_ylim([-0.05, 1.05])
    ax1.legend(loc="lower right")
    plt.rc('axes', labelsize=22)    # fontsize of the x and y labels
    plt.rc('xtick', labelsize=15)    # fontsize of the tick labels
    plt.rc('ytick', labelsize=15)    # fontsize of the tick labels
    plt.rc('legend', fontsize=20)    # legend fontsize
    #save figure in hi-resolution
    plt.savefig(path + filename + ".eps",  dpi=400,  transparent=True)

def onc_plot_roc_no_threshold(y_true, y_pred, model_name, **kwargs):
    ''' 
    Plot the ROC AUC and return the test ROC AUC results.
    INPUT: y_true, y_pred, model_name, **kwargs
    OUTPUT: false_positives, true_positives
    '''

    #calc values for plot
    false_positives, true_positives, threshold = roc_curve(y_true, y_pred)
    c_roc_auc_score = auc(false_positives, true_positives)
    
    #set figure params
    fig1 = plt.figure(1, figsize=(12,30),dpi=1000)
    ax1 = plt.subplot2grid((7, 1), (0, 0), rowspan=2)
    
    #plot reference line for chance
    ax1.plot([0, 1], [0, 1], linestyle='--', lw=2, color='gray',
        label='Chance', alpha=.8)
    
    # plot AUC ROC
    ax1.plot(false_positives, true_positives, 
        label=r'ROC (AUC = %0.3f)' % (c_roc_auc_score),
        lw=2, alpha=.8, color = 'k')
    
    
    # additional figure params
    ax1.set(xlim=[-0.05, 1.05], ylim=[-0.05, 1.05],)
    ax1.legend(loc="lower right")
    plt.xlabel('1-Specificity')
    plt.ylabel('Sensitivity')
    plt.rc('axes', labelsize=22)    # fontsize of the x and y labels
    plt.rc('xtick', labelsize=15)    # fontsize of the tick labels
    plt.rc('ytick', labelsize=15)    # fontsize of the tick labels
    plt.rc('legend', fontsize=20)    # legend fontsize
    # save plot
    plt.savefig(model_name + "_roc_auc_bw_nothreshold_hires.png",  dpi=1000,  transparent=True)
    plt.savefig(model_name + "_roc_auc_bw_nothreshold_hires.eps",  dpi=1000,  transparent=False)
    plt.savefig(model_name + "_roc_auc_bw_nothreshold_hires.svg",  dpi=1000,  transparent=False)