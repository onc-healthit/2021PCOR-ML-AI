import pandas as pd

def get_risk_categories(dataset, y_proba_col_name, y_true_col_name):
    
    test_x_pd = dataset[dataset.subset > 6].copy().sort_values(by = 'usrds_id')
    del dataset
    
    df = test_x_pd.loc[:,[y_true_col_name,y_proba_col_name]]
    
    #construct the risk categories from the predicted score
    df['risk_categories'] = pd.cut(df[y_proba_col_name],        
                                   bins=[-0.1, 0.09, 0.19, 0.29, 0.39, 0.49, 0.59, 0.69, 0.79, 0.89, 0.99],
                                   labels=['0-0.09', '0.1-0.19', '0.2-0.29', '0.3-0.39', '0.4-0.49',
                                           '0.5-0.59','0.6-0.69','0.7-0.79','0.8-0.89','0.9-0.99'])
    
    #loop through all the categories to get the predicted score
    risk_list = []
    for name, c in df.groupby('risk_categories'):
        risk_dict = {}
        risk_dict['Risk Category'] = name
        risk_dict['Count'] = c[y_true_col_name].shape[0]
        risk_dict['Count Died in 90'] = c[y_true_col_name].sum()
        risk_dict['Count Survived'] = c[y_true_col_name].shape[0]-c[y_true_col_name].sum()
        risk_dict['Percent Died in 90'] = c[y_true_col_name].sum()/c[y_true_col_name].shape[0]
        
        risk_list.append(risk_dict)
    
    df_risk = pd.DataFrame(risk_list)
    return df_risk