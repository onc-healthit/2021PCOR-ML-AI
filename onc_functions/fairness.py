import pandas as pd
import numpy as np
from sklearn.metrics import  roc_auc_score, confusion_matrix

def get_fairness_assessment(df, y_proba_col_name, y_true_col_name):
    
    #turn the continuous age variable into age categories
    df['agegroup'] = pd.cut(df.inc_age, 
                           bins=[17, 25, 35, 45, 55, 65, 75, 85, 90], 
                           labels=[1, 2, 3, 4, 5, 6, 7, 8])
    
    df = df.drop(columns=['inc_age'])
    
    #replace NaNs with a large number that does not appear in the data, effectively creating another category for missing values
    df.loc[:,['race','dialtyp','hispanic']] = df.loc[:,['race','dialtyp','hispanic']].fillna(100.0, axis=1).copy()
    
    #Identify the cols for the fairness assessment
    fairness_cols = ['agegroup', 'sex','dialtyp', 'race','hispanic']
    
    #loop through all categories and values to get counts, auc, and confusion matrix
    rows_list = []
    for col in fairness_cols:
        for name, c in df.groupby(col):
            fairness_dict = {}
            fairness_dict['Feature'] = col
            fairness_dict['Value'] = name
            fairness_dict['Count'] = c.shape[0]

            fairness_dict['AUC'] = roc_auc_score(c[y_true_col_name], c[y_proba_col_name])
            tn, fp, fn, tp = confusion_matrix(y_true = c[y_true_col_name], 
                                              y_pred = np.where(c[y_proba_col_name] >= 0.5, 1, 0)).ravel()
            fairness_dict['TN'] = tn
            fairness_dict['FP'] = fp
            fairness_dict['FN'] = fn
            fairness_dict['TP'] = tp
            rows_list.append(fairness_dict)
    
    #convert results from a list to a dataframe
    df_fairness = pd.DataFrame(rows_list)
    return df_fairness
